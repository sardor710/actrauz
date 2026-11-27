// The same fixture as app/test/helpers.dart: one venue in Tashkent open
// 07:00-23:00 every day, one 90-minute padel court at 180 000.

export async function addCities(pool) {
  await pool.query(`
    insert into cities (id, name_en, country_code, currency, utc_offset_minutes) values
      ('tashkent', 'Tashkent', 'UZ', 'UZS', 300),
      ('almaty', 'Almaty', 'KZ', 'KZT', 300),
      ('farcity', 'Far City', 'KZ', 'KZT', 360)
    on conflict (id) do nothing`);
  await pool.query(`
    insert into sports (id, name_en, icon_key, default_players) values
      ('padel', 'Padel', 'padel', 4), ('football', 'Football', 'football', 10)
    on conflict (id) do nothing`);
}

/**
 * Padel and tennis as rated sports (M7), as in production. Only the M7 test
 * files call it: older files rely on padel being a simple-level sport.
 */
export async function addRatedSports(pool) {
  await addCities(pool);
  await pool.query(`update sports set competitive_rating = true where id = 'padel'`);
  await pool.query(`
    insert into sports (id, name_en, icon_key, default_players, competitive_rating) values
      ('tennis', 'Tennis', 'tennis', 2, true)
    on conflict (id) do update set competitive_rating = true`);
}

/** hours: { weekday: [openMinute, closeMinute] | null }; default 07:00-23:00 all week. */
export async function addVenue(pool, { cityId = 'tashkent', name = 'Test venue', open = 7 * 60, close = 23 * 60, hours } = {}) {
  await addCities(pool);
  const { rows } = await pool.query(`insert into venues (city_id, name_en) values ($1, $2) returning id`, [cityId, name]);
  const venueId = rows[0].id;
  for (let weekday = 1; weekday <= 7; weekday++) {
    const day = hours ? hours[weekday] : [open, close];
    if (!day) continue;
    await pool.query(`insert into working_hours (venue_id, weekday, open_minute, close_minute) values ($1, $2, $3, $4)`, [
      venueId,
      weekday,
      day[0],
      day[1],
    ]);
  }
  return venueId;
}

/**
 * rules: [{ weekdays, from, to, price }] in priority order.
 * override: { weekday: [open, close] | null } replaces the venue's hours.
 */
export async function addCourt(pool, venueId, { slot = 90, basePrice = 180000, rules = [], override = {}, sportId = 'padel' } = {}) {
  const { rows } = await pool.query(
    `insert into courts (venue_id, sport_id, name_en, slot_minutes, base_price) values ($1, $2, 'Court', $3, $4) returning id`,
    [venueId, sportId, slot, basePrice],
  );
  const courtId = rows[0].id;
  for (const [i, rule] of rules.entries()) {
    await pool.query(
      `insert into price_rules (court_id, weekdays, from_minute, to_minute, price, sort_order) values ($1, $2, $3, $4, $5, $6)`,
      [courtId, rule.weekdays, rule.from, rule.to, rule.price, i],
    );
  }
  for (const [weekday, day] of Object.entries(override)) {
    await pool.query(
      `insert into working_hours (court_id, weekday, closed, open_minute, close_minute) values ($1, $2, $3, $4, $5)`,
      [courtId, Number(weekday), day === null, day?.[0] ?? 0, day?.[1] ?? 0],
    );
  }
  return courtId;
}

/** Makes an existing user an owner of the venue (a row in venue_owners). */
export async function addOwner(pool, venueId, userId) {
  await pool.query(`insert into venue_owners (venue_id, user_id) values ($1, $2)`, [venueId, userId]);
  return userId;
}

/** Makes an existing user an admin (a row in app_admins): acts on every venue. */
export async function addAdmin(pool, userId) {
  await pool.query(`insert into app_admins (user_id) values ($1)`, [userId]);
  return userId;
}

/** Gives an existing user the account phone number `phone` ("+998901111111"). */
export async function addPhone(pool, userId, phone) {
  await pool.query(`insert into profile_contacts (user_id, phone) values ($1, $2)`, [userId, phone]);
  return userId;
}

const pad = (n) => String(n).padStart(2, '0');

/** Venue wall-clock time, as the API carries it: "2026-11-23T07:00:00". */
export const at = (day, hour, minute = 0) => `${day}T${pad(hour)}:${pad(minute)}:00`;

/** The instant of a Tashkent (UTC+5) wall-clock time, for the `now` argument. */
export const tashkent = (day, hour, minute = 0) => `${day}T${pad(hour)}:${pad(minute)}:00+05:00`;

export const monday = '2026-11-23';
export const saturday = '2026-11-28';

/**
 * A tournament written straight to the table (M8 tests): in the venue's city,
 * or Tashkent without a venue. Registration closes at 00:00 on startsOn.
 */
export async function addTournament(pool, { sportId = 'padel', venueId = null, startsOn = '2026-12-10', endsOn = startsOn } = {}) {
  await addCities(pool);
  const { rows } = await pool.query(
    `insert into tournaments (city_id, sport_id, venue_id, title_en, title_ru, title_uz, starts_on, ends_on)
     values (coalesce((select v.city_id from venues v where v.id = $2), 'tashkent'), $1, $2, 'Cup', 'Кубок', 'Kubok', $3, $4)
     returning id`,
    [sportId, venueId, startsOn, endsOn],
  );
  return rows[0].id;
}

/** A category of the tournament (open levels, no fee). */
export async function addCategory(pool, tournamentId, { kind = 'singles', cap = 32 } = {}) {
  const { rows } = await pool.query(
    `insert into tournament_categories (tournament_id, name_en, name_ru, name_uz, kind, cap)
     values ($1, $2, $2, $2, $3, $4) returning id`,
    [tournamentId, kind === 'pairs' ? 'Pairs' : 'Singles', kind, cap],
  );
  return rows[0].id;
}

/**
 * One `registered` entry per user, in order; partners[i] (pairs) is the
 * confirmed partner of users[i]. Returns the registration ids.
 */
export async function addEntries(pool, categoryId, users, { partners = [] } = {}) {
  const ids = [];
  for (const [i, userId] of users.entries()) {
    const partnerId = partners[i] ?? null;
    const { rows } = await pool.query(
      `insert into tournament_registrations (category_id, user_id, partner_id, partner_confirmed, status, fee, currency, created_at, decided_at)
       values ($1, $2, $3, true, 'registered', 0, 'UZS', now(), now()) returning id`,
      [categoryId, userId, partnerId],
    );
    ids.push(rows[0].id);
  }
  return ids;
}
