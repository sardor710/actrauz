-- Sample content for a new Actra database.
--
-- GENERATED from app/lib/data/sample/sample_data.dart. Do not edit by hand:
--   cd app && dart run tool/gen_seed.dart
--
-- Safe to run again at any time; sample games and tournaments are re-dated
-- from today, except a tournament anyone has registered for, which keeps its
-- dates and categories. Venues, people and banners are fictional.

-- Cities
insert into public.cities (id, name_uz, name_ru, name_kk, name_en, country_code, currency, utc_offset_minutes) values
  ('tashkent', 'Toshkent', 'Ташкент', 'Ташкент', 'Tashkent', 'UZ', 'UZS', 300),
  ('almaty', 'Olmaota', 'Алматы', 'Алматы', 'Almaty', 'KZ', 'KZT', 300),
  ('astana', 'Ostona', 'Астана', 'Астана', 'Astana', 'KZ', 'KZT', 300)
on conflict (id) do update set name_uz = excluded.name_uz, name_ru = excluded.name_ru, name_kk = excluded.name_kk, name_en = excluded.name_en, country_code = excluded.country_code, currency = excluded.currency, utc_offset_minutes = excluded.utc_offset_minutes;

-- Sports
insert into public.sports (id, name_uz, name_ru, name_kk, name_en, icon_key, bookable, competitive_rating, default_players, sort_order) values
  ('football', 'Futbol', 'Футбол', 'Футбол', 'Football', 'football', true, false, 10, 0),
  ('padel', 'Padel', 'Падел', 'Падел', 'Padel', 'padel', true, true, 4, 1),
  ('tennis', 'Tennis', 'Теннис', 'Теннис', 'Tennis', 'tennis', true, true, 2, 2),
  ('basketball', 'Basketbol', 'Баскетбол', 'Баскетбол', 'Basketball', 'basketball', true, false, 10, 3),
  ('volleyball', 'Voleybol', 'Волейбол', 'Волейбол', 'Volleyball', 'volleyball', true, false, 12, 4),
  ('running', 'Yugurish', 'Бег', 'Жүгіру', 'Running', 'running', false, false, 4, 5),
  ('gym', 'Sport zali', 'Тренажёрный зал', 'Жаттығу залы', 'Gym', 'gym', false, false, 2, 6)
on conflict (id) do update set name_uz = excluded.name_uz, name_ru = excluded.name_ru, name_kk = excluded.name_kk, name_en = excluded.name_en, icon_key = excluded.icon_key, bookable = excluded.bookable, competitive_rating = excluded.competitive_rating, default_players = excluded.default_players, sort_order = excluded.sort_order;

-- Venues
insert into public.venues (id, city_id, name_uz, name_ru, name_kk, name_en, description_uz, description_ru, description_kk, description_en, address_uz, address_ru, address_kk, address_en, district_uz, district_ru, district_kk, district_en, phone, amenities, color_seed) values
  (md5('actra:v1')::uuid, 'tashkent', 'Lochin Padel Club', 'Lochin Padel Club', null, 'Lochin Padel Club', 'Ikki yopiq padel korti, panoramali oynalar va professional yoritish.', 'Два крытых падел-корта с панорамным стеклом и профессиональным освещением.', null, 'Two indoor padel courts with panoramic glass and professional lighting.', 'Bogʻishamol koʻchasi, 12', 'улица Богишамол, 12', null, '12 Bogishamol Street', 'Yunusobod', 'Юнусабад', null, 'Yunusabad', '+998 71 200 00 01', array['parking', 'showers', 'lighting', 'rental']::text[], 0),
  (md5('actra:v2')::uuid, 'tashkent', 'Bunyod Football Park', 'Bunyod Football Park', null, 'Bunyod Football Park', 'Sunʼiy qoplamali ikki maydon: 5×5 va 7×7. Kechki oʻyinlar uchun yoritish bor.', 'Два поля с искусственным покрытием: 5×5 и 7×7. Есть освещение для вечерних игр.', null, 'Two artificial-turf pitches: 5-a-side and 7-a-side, with floodlights for evening games.', 'Qatortol koʻchasi, 48', 'улица Катартал, 48', null, '48 Qatortol Street', 'Chilonzor', 'Чиланзар', null, 'Chilanzar', '+998 71 200 00 02', array['parking', 'lighting', 'cafe']::text[], 1),
  (md5('actra:v3')::uuid, 'tashkent', 'Semurg Tennis Centre', 'Semurg Tennis Centre', null, 'Semurg Tennis Centre', 'Ochiq tennis kortlari va basketbol maydonchasi. Ertalabki mashgʻulotlar uchun qulay.', 'Открытые теннисные корты и баскетбольная площадка. Удобно для утренних тренировок.', null, 'Outdoor tennis courts and a basketball court. Good for early-morning sessions.', 'Buyuk Ipak Yoʻli koʻchasi, 105', 'улица Буюк Ипак Йули, 105', null, '105 Buyuk Ipak Yoli Street', 'Mirzo Ulugʻbek', 'Мирзо-Улугбек', null, 'Mirzo Ulugbek', '+998 71 200 00 03', array['showers', 'rental', 'cafe']::text[], 2),
  (md5('actra:v4')::uuid, 'almaty', 'Alatau Padel & Tennis', 'Alatau Padel & Tennis', null, 'Alatau Padel & Tennis', 'Togʻ manzarali padel va tennis kortlari.', 'Падел и теннисные корты с видом на горы.', null, 'Padel and tennis courts with a mountain view.', 'Timiryazev koʻchasi, 42', 'улица Тимирязева, 42', null, '42 Timiryazev Street', 'Bostandiq', 'Бостандыкский район', null, 'Bostandyk', '+7 727 200 00 04', array['parking', 'showers', 'lighting', 'rental', 'cafe']::text[], 3),
  (md5('actra:v5')::uuid, 'almaty', 'Zhetisu Arena', 'Zhetisu Arena', null, 'Zhetisu Arena', 'Futbol va voleybol uchun yopiq zal. Yakshanba kuni dam olish kuni.', 'Крытый зал для футбола и волейбола. Воскресенье — выходной.', null, 'Indoor hall for football and volleyball. Closed on Sundays.', 'Dostiq shoh koʻchasi, 210', 'проспект Достык, 210', null, '210 Dostyk Avenue', 'Medeu', 'Медеуский район', null, 'Medeu', '+7 727 200 00 05', array['parking', 'showers']::text[], 4),
  (md5('actra:v6')::uuid, 'astana', 'Esil Sport Hub', 'Esil Sport Hub', null, 'Esil Sport Hub', 'Yil boʻyi ishlaydigan yopiq majmua: futbol, basketbol va padel.', 'Крытый комплекс, работающий круглый год: футбол, баскетбол и падел.', null, 'Indoor complex open all year: football, basketball and padel.', 'Qabanbay botir shoh koʻchasi, 60', 'проспект Кабанбай батыра, 60', null, '60 Kabanbay Batyr Avenue', 'Esil', 'район Есиль', null, 'Esil', '+7 7172 20 00 06', array['parking', 'showers', 'lighting', 'cafe']::text[], 5)
on conflict (id) do update set city_id = excluded.city_id, name_uz = excluded.name_uz, name_ru = excluded.name_ru, name_kk = excluded.name_kk, name_en = excluded.name_en, description_uz = excluded.description_uz, description_ru = excluded.description_ru, description_kk = excluded.description_kk, description_en = excluded.description_en, address_uz = excluded.address_uz, address_ru = excluded.address_ru, address_kk = excluded.address_kk, address_en = excluded.address_en, district_uz = excluded.district_uz, district_ru = excluded.district_ru, district_kk = excluded.district_kk, district_en = excluded.district_en, phone = excluded.phone, amenities = excluded.amenities, color_seed = excluded.color_seed;

-- Courts
insert into public.courts (id, venue_id, sport_id, name_uz, name_ru, name_kk, name_en, slot_minutes, base_price, indoor, sort_order) values
  (md5('actra:v1c1')::uuid, md5('actra:v1')::uuid, 'padel', 'Kort 1', 'Корт 1', null, 'Court 1', 90, 180000, true, 0),
  (md5('actra:v1c2')::uuid, md5('actra:v1')::uuid, 'padel', 'Kort 2', 'Корт 2', null, 'Court 2', 90, 180000, true, 1),
  (md5('actra:v2c1')::uuid, md5('actra:v2')::uuid, 'football', 'Maydon 5×5', 'Поле 5×5', null, 'Pitch 5×5', 60, 250000, false, 0),
  (md5('actra:v2c2')::uuid, md5('actra:v2')::uuid, 'football', 'Maydon 7×7', 'Поле 7×7', null, 'Pitch 7×7', 60, 400000, false, 1),
  (md5('actra:v3c1')::uuid, md5('actra:v3')::uuid, 'tennis', 'Kort A', 'Корт A', null, 'Court A', 60, 120000, false, 0),
  (md5('actra:v3c2')::uuid, md5('actra:v3')::uuid, 'tennis', 'Kort B', 'Корт B', null, 'Court B', 60, 120000, false, 1),
  (md5('actra:v3c3')::uuid, md5('actra:v3')::uuid, 'basketball', 'Basketbol maydonchasi', 'Баскетбольная площадка', null, 'Basketball court', 60, 200000, false, 2),
  (md5('actra:v4c1')::uuid, md5('actra:v4')::uuid, 'padel', 'Padel korti', 'Падел-корт', null, 'Padel court', 90, 12000, true, 0),
  (md5('actra:v4c2')::uuid, md5('actra:v4')::uuid, 'tennis', 'Tennis korti', 'Теннисный корт', null, 'Tennis court', 60, 8000, false, 1),
  (md5('actra:v5c1')::uuid, md5('actra:v5')::uuid, 'football', 'Futbol zali', 'Футбольный зал', null, 'Football hall', 60, 15000, true, 0),
  (md5('actra:v5c2')::uuid, md5('actra:v5')::uuid, 'volleyball', 'Voleybol zali', 'Волейбольный зал', null, 'Volleyball hall', 60, 9000, true, 1),
  (md5('actra:v6c1')::uuid, md5('actra:v6')::uuid, 'football', 'Futbol maydoni', 'Футбольное поле', null, 'Football pitch', 60, 14000, true, 0),
  (md5('actra:v6c2')::uuid, md5('actra:v6')::uuid, 'basketball', 'Basketbol zali', 'Баскетбольный зал', null, 'Basketball hall', 60, 10000, true, 1),
  (md5('actra:v6c3')::uuid, md5('actra:v6')::uuid, 'padel', 'Padel korti', 'Падел-корт', null, 'Padel court', 90, 13000, true, 2)
on conflict (id) do update set venue_id = excluded.venue_id, sport_id = excluded.sport_id, name_uz = excluded.name_uz, name_ru = excluded.name_ru, name_kk = excluded.name_kk, name_en = excluded.name_en, slot_minutes = excluded.slot_minutes, base_price = excluded.base_price, indoor = excluded.indoor, sort_order = excluded.sort_order;

-- Working hours: a venue row per open weekday; a court row only where it differs.
delete from public.working_hours where venue_id in (md5('actra:v1')::uuid, md5('actra:v2')::uuid, md5('actra:v3')::uuid, md5('actra:v4')::uuid, md5('actra:v5')::uuid, md5('actra:v6')::uuid);
delete from public.working_hours where court_id in (md5('actra:v1c1')::uuid, md5('actra:v1c2')::uuid, md5('actra:v2c1')::uuid, md5('actra:v2c2')::uuid, md5('actra:v3c1')::uuid, md5('actra:v3c2')::uuid, md5('actra:v3c3')::uuid, md5('actra:v4c1')::uuid, md5('actra:v4c2')::uuid, md5('actra:v5c1')::uuid, md5('actra:v5c2')::uuid, md5('actra:v6c1')::uuid, md5('actra:v6c2')::uuid, md5('actra:v6c3')::uuid);
insert into public.working_hours (venue_id, court_id, weekday, closed, open_minute, close_minute) values
  (md5('actra:v1')::uuid, null, 1, false, 420, 1380),
  (md5('actra:v1')::uuid, null, 2, false, 420, 1380),
  (md5('actra:v1')::uuid, null, 3, false, 420, 1380),
  (md5('actra:v1')::uuid, null, 4, false, 420, 1380),
  (md5('actra:v1')::uuid, null, 5, false, 420, 1380),
  (md5('actra:v1')::uuid, null, 6, false, 420, 1380),
  (md5('actra:v1')::uuid, null, 7, false, 420, 1380),
  (md5('actra:v2')::uuid, null, 1, false, 480, 1440),
  (md5('actra:v2')::uuid, null, 2, false, 480, 1440),
  (md5('actra:v2')::uuid, null, 3, false, 480, 1440),
  (md5('actra:v2')::uuid, null, 4, false, 480, 1440),
  (md5('actra:v2')::uuid, null, 5, false, 480, 1440),
  (md5('actra:v2')::uuid, null, 6, false, 540, 1380),
  (md5('actra:v2')::uuid, null, 7, false, 540, 1380),
  (md5('actra:v3')::uuid, null, 1, false, 390, 1350),
  (md5('actra:v3')::uuid, null, 2, false, 390, 1350),
  (md5('actra:v3')::uuid, null, 3, false, 390, 1350),
  (md5('actra:v3')::uuid, null, 4, false, 390, 1350),
  (md5('actra:v3')::uuid, null, 5, false, 390, 1350),
  (md5('actra:v3')::uuid, null, 6, false, 390, 1350),
  (md5('actra:v3')::uuid, null, 7, false, 390, 1350),
  (null, md5('actra:v3c3')::uuid, 1, true, 0, 0),
  (md5('actra:v4')::uuid, null, 1, false, 420, 1380),
  (md5('actra:v4')::uuid, null, 2, false, 420, 1380),
  (md5('actra:v4')::uuid, null, 3, false, 420, 1380),
  (md5('actra:v4')::uuid, null, 4, false, 420, 1380),
  (md5('actra:v4')::uuid, null, 5, false, 420, 1380),
  (md5('actra:v4')::uuid, null, 6, false, 420, 1380),
  (md5('actra:v4')::uuid, null, 7, false, 420, 1380),
  (md5('actra:v5')::uuid, null, 1, false, 480, 1320),
  (md5('actra:v5')::uuid, null, 2, false, 480, 1320),
  (md5('actra:v5')::uuid, null, 3, false, 480, 1320),
  (md5('actra:v5')::uuid, null, 4, false, 480, 1320),
  (md5('actra:v5')::uuid, null, 5, false, 480, 1320),
  (md5('actra:v5')::uuid, null, 6, false, 540, 1200),
  (md5('actra:v6')::uuid, null, 1, false, 480, 1380),
  (md5('actra:v6')::uuid, null, 2, false, 480, 1380),
  (md5('actra:v6')::uuid, null, 3, false, 480, 1380),
  (md5('actra:v6')::uuid, null, 4, false, 480, 1380),
  (md5('actra:v6')::uuid, null, 5, false, 480, 1380),
  (md5('actra:v6')::uuid, null, 6, false, 480, 1380),
  (md5('actra:v6')::uuid, null, 7, false, 480, 1380);

-- Price rules, in priority order
delete from public.price_rules where court_id in (md5('actra:v1c1')::uuid, md5('actra:v1c2')::uuid, md5('actra:v2c1')::uuid, md5('actra:v2c2')::uuid, md5('actra:v3c1')::uuid, md5('actra:v3c2')::uuid, md5('actra:v3c3')::uuid, md5('actra:v4c1')::uuid, md5('actra:v4c2')::uuid, md5('actra:v5c1')::uuid, md5('actra:v5c2')::uuid, md5('actra:v6c1')::uuid, md5('actra:v6c2')::uuid, md5('actra:v6c3')::uuid);
insert into public.price_rules (court_id, weekdays, from_minute, to_minute, price, sort_order) values
  (md5('actra:v1c1')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 250000, 0),
  (md5('actra:v1c1')::uuid, array[6, 7], 0, 1440, 300000, 1),
  (md5('actra:v1c2')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 250000, 0),
  (md5('actra:v1c2')::uuid, array[6, 7], 0, 1440, 300000, 1),
  (md5('actra:v2c1')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 350000, 0),
  (md5('actra:v2c2')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 520000, 0),
  (md5('actra:v3c1')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 160000, 0),
  (md5('actra:v3c2')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 160000, 0),
  (md5('actra:v4c1')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 16000, 0),
  (md5('actra:v4c1')::uuid, array[6, 7], 0, 1440, 18000, 1),
  (md5('actra:v4c2')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 11000, 0),
  (md5('actra:v5c1')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 20000, 0),
  (md5('actra:v6c1')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 19000, 0),
  (md5('actra:v6c3')::uuid, array[1, 2, 3, 4, 5], 1080, 1440, 17000, 0);

-- Banners (shown in every city)
insert into public.banners (id, title_uz, title_ru, title_kk, title_en, subtitle_uz, subtitle_ru, subtitle_kk, subtitle_en, url, color_seed, sort_order) values
  (md5('actra:bn1')::uuid, 'Onlayn band qiling, joyida toʻlang', 'Бронируйте онлайн, платите на месте', null, 'Book online, pay at the venue', 'Boʻsh vaqtlar real vaqtda koʻrinadi', 'Свободное время видно сразу', null, 'See free times instantly', 'https://example.com/actra/how-it-works', 0, 0),
  (md5('actra:bn2')::uuid, 'Sherik topilmayaptimi?', 'Не с кем играть?', null, 'Nobody to play with?', 'Oʻz darajangizdagi oʻyinga qoʻshiling', 'Присоединяйтесь к игре своего уровня', null, 'Join a game at your level', 'https://example.com/actra/games', 3, 1)
on conflict (id) do update set title_uz = excluded.title_uz, title_ru = excluded.title_ru, title_kk = excluded.title_kk, title_en = excluded.title_en, subtitle_uz = excluded.subtitle_uz, subtitle_ru = excluded.subtitle_ru, subtitle_kk = excluded.subtitle_kk, subtitle_en = excluded.subtitle_en, url = excluded.url, color_seed = excluded.color_seed, sort_order = excluded.sort_order;

-- Tournaments, dated from today. The summary columns (min_fee, max_fee, slots_total,
-- slots_filled) are not written: the last statement of this file recomputes them.
insert into public.tournaments (id, city_id, sport_id, venue_id, title_uz, title_ru, title_kk, title_en, starts_on, ends_on, registration_deadline) values
  (md5('actra:t1')::uuid, 'tashkent', 'padel', md5('actra:v1')::uuid, 'Toshkent Padel Kubogi', 'Кубок Ташкента по паделу', null, 'Tashkent Padel Cup', (select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'tashkent') + 12, (select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'tashkent') + 13, app.to_instant(((select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'tashkent') + 10)::timestamp + interval '18 hours', (select c.utc_offset_minutes from public.cities c where c.id = 'tashkent'))),
  (md5('actra:t2')::uuid, 'tashkent', 'football', md5('actra:v2')::uuid, 'Havaskorlar ligasi 5×5', 'Любительская лига 5×5', null, 'Amateur 5-a-side League', (select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'tashkent') + 20, (select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'tashkent') + 20, app.to_instant(((select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'tashkent') + 18)::timestamp + interval '18 hours', (select c.utc_offset_minutes from public.cities c where c.id = 'tashkent'))),
  (md5('actra:t3')::uuid, 'almaty', 'tennis', md5('actra:v4')::uuid, 'Olmaota ochiq tennis turniri', 'Открытый теннисный турнир Алматы', null, 'Almaty Open Tennis', (select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'almaty') + 15, (select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'almaty') + 17, app.to_instant(((select app.to_local(now(), c.utc_offset_minutes)::date from public.cities c where c.id = 'almaty') + 13)::timestamp + interval '18 hours', (select c.utc_offset_minutes from public.cities c where c.id = 'almaty')))
on conflict (id) do update set city_id = excluded.city_id, sport_id = excluded.sport_id, venue_id = excluded.venue_id, title_uz = excluded.title_uz, title_ru = excluded.title_ru, title_kk = excluded.title_kk, title_en = excluded.title_en, starts_on = excluded.starts_on, ends_on = excluded.ends_on, registration_deadline = excluded.registration_deadline
  where not exists (select 1 from public.tournament_registrations r join public.tournament_categories c on c.id = r.category_id where c.tournament_id = excluded.id);

-- Tournament categories (the first of each is the default category the migration made)
insert into public.tournament_categories (id, tournament_id, name_uz, name_ru, name_kk, name_en, kind, gender, min_level, max_level, fee, cap, waitlist_enabled, sort_order) values
  (md5('actra:default-category:' || md5('actra:t1')::uuid::text)::uuid, md5('actra:t1')::uuid, 'Ochiq juftliklar', 'Открытые пары', null, 'Open pairs', 'pairs', 'open', 1, 5, 300000, 12, true, 0),
  (md5('actra:t1c2')::uuid, md5('actra:t1')::uuid, 'Erkaklar juftliklari', 'Мужские пары', null, 'Men''s pairs', 'pairs', 'men', 3, 5, 500000, 8, true, 1),
  (md5('actra:t1c3')::uuid, md5('actra:t1')::uuid, 'Aralash juftliklar', 'Смешанные пары', null, 'Mixed pairs', 'pairs', 'mixed', 2, 4, 400000, 12, true, 2),
  (md5('actra:default-category:' || md5('actra:t2')::uuid::text)::uuid, md5('actra:t2')::uuid, 'Ochiq', 'Открытая', null, 'Open', 'singles', 'open', 1, 5, 800000, 12, true, 0),
  (md5('actra:default-category:' || md5('actra:t3')::uuid::text)::uuid, md5('actra:t3')::uuid, 'Ochiq, yakkalik', 'Открытая, одиночный', null, 'Open singles', 'singles', 'open', 1, 5, 15000, 16, true, 0),
  (md5('actra:t3c2')::uuid, md5('actra:t3')::uuid, 'Erkaklar, yakkalik', 'Мужчины, одиночный', null, 'Men''s singles', 'singles', 'men', 3, 5, 25000, 8, true, 1)
on conflict (id) do update set tournament_id = excluded.tournament_id, name_uz = excluded.name_uz, name_ru = excluded.name_ru, name_kk = excluded.name_kk, name_en = excluded.name_en, kind = excluded.kind, gender = excluded.gender, min_level = excluded.min_level, max_level = excluded.max_level, fee = excluded.fee, cap = excluded.cap, waitlist_enabled = excluded.waitlist_enabled, sort_order = excluded.sort_order
  where not exists (select 1 from public.tournament_registrations r where r.category_id = excluded.id);

-- Sample players. They have no password and an undeliverable address,
-- so nobody can sign in as them.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change) values
  ('00000000-0000-0000-0000-000000000000', md5('actra:p1')::uuid, 'authenticated', 'authenticated', 'p1@seed.actra.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', md5('actra:p2')::uuid, 'authenticated', 'authenticated', 'p2@seed.actra.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', md5('actra:p3')::uuid, 'authenticated', 'authenticated', 'p3@seed.actra.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', md5('actra:p4')::uuid, 'authenticated', 'authenticated', 'p4@seed.actra.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', md5('actra:p5')::uuid, 'authenticated', 'authenticated', 'p5@seed.actra.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', md5('actra:p6')::uuid, 'authenticated', 'authenticated', 'p6@seed.actra.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', md5('actra:p7')::uuid, 'authenticated', 'authenticated', 'p7@seed.actra.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', md5('actra:p8')::uuid, 'authenticated', 'authenticated', 'p8@seed.actra.invalid', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"sample":true}'::jsonb, now(), now(), '', '', '', '')
on conflict (id) do nothing;

insert into public.profiles (id, full_name, language) values
  (md5('actra:p1')::uuid, 'Aziz', 'ru'),
  (md5('actra:p2')::uuid, 'Dilnoza', 'ru'),
  (md5('actra:p3')::uuid, 'Timur', 'ru'),
  (md5('actra:p4')::uuid, 'Madina', 'ru'),
  (md5('actra:p5')::uuid, 'Arman', 'ru'),
  (md5('actra:p6')::uuid, 'Aigerim', 'ru'),
  (md5('actra:p7')::uuid, 'Bekzod', 'ru'),
  (md5('actra:p8')::uuid, 'Kamila', 'ru')
on conflict (id) do update set full_name = excluded.full_name, language = excluded.language;

insert into public.player_levels (user_id, sport_id, level) values
  (md5('actra:p1')::uuid, 'padel', 3),
  (md5('actra:p1')::uuid, 'football', 3),
  (md5('actra:p2')::uuid, 'padel', 2),
  (md5('actra:p2')::uuid, 'tennis', 3),
  (md5('actra:p3')::uuid, 'football', 4),
  (md5('actra:p4')::uuid, 'tennis', 4),
  (md5('actra:p5')::uuid, 'padel', 3),
  (md5('actra:p6')::uuid, 'football', 2),
  (md5('actra:p7')::uuid, 'football', 3),
  (md5('actra:p7')::uuid, 'padel', 4),
  (md5('actra:p8')::uuid, 'padel', 3),
  (md5('actra:p8')::uuid, 'tennis', 2)
on conflict (user_id, sport_id) do update set level = excluded.level;

insert into public.player_ratings (user_id, sport_id, rating, rated_games, source) values
  (md5('actra:p1')::uuid, 'padel', 3.50, 12, 'level'),
  (md5('actra:p2')::uuid, 'padel', 2.50, 4, 'level'),
  (md5('actra:p2')::uuid, 'tennis', 3.50, 4, 'level'),
  (md5('actra:p4')::uuid, 'tennis', 4.50, 12, 'level'),
  (md5('actra:p5')::uuid, 'padel', 3.50, 12, 'level'),
  (md5('actra:p7')::uuid, 'padel', 4.50, 12, 'level'),
  (md5('actra:p8')::uuid, 'padel', 3.50, 12, 'level'),
  (md5('actra:p8')::uuid, 'tennis', 2.50, 12, 'level')
on conflict (user_id, sport_id) do update set rating = excluded.rating, rated_games = excluded.rated_games, source = excluded.source;

-- Sample games. Each sits on a real booking made through the booking
-- functions, so its slot shows as taken. Recreated on every run.
delete from public.games where host_id in (md5('actra:p1')::uuid, md5('actra:p2')::uuid, md5('actra:p3')::uuid, md5('actra:p4')::uuid, md5('actra:p5')::uuid, md5('actra:p6')::uuid, md5('actra:p7')::uuid, md5('actra:p8')::uuid);
delete from public.bookings where user_id in (md5('actra:p1')::uuid, md5('actra:p2')::uuid, md5('actra:p3')::uuid, md5('actra:p4')::uuid, md5('actra:p5')::uuid, md5('actra:p6')::uuid, md5('actra:p7')::uuid, md5('actra:p8')::uuid);

create function pg_temp.actra_seed_game(
  p_game_id uuid, p_court_id uuid, p_days_ahead integer, p_minute_of_day integer,
  p_spots integer, p_min_level integer, p_max_level integer, p_players uuid[])
returns void
language plpgsql
as $$
declare
  v_now timestamptz := now();
  v_venue_id uuid;
  v_sport_id text;
  v_city_id text;
  v_offset integer;
  v_start timestamp;
  v_booking public.bookings;
  v_min_rating numeric;
  v_max_rating numeric;
begin
  select c.venue_id, c.sport_id, v.city_id, ci.utc_offset_minutes
    into v_venue_id, v_sport_id, v_city_id, v_offset
  from public.courts c
  join public.venues v on v.id = c.venue_id
  join public.cities ci on ci.id = v.city_id
  where c.id = p_court_id;

  v_start := app.to_local(v_now, v_offset)::date + make_interval(days => p_days_ahead, mins => p_minute_of_day);
  begin
    -- The first player is the host and holds the booking.
    v_booking := app.hold_slots(p_players[1], p_court_id, array[v_start], v_now);
    v_booking := app.confirm_booking(p_players[1], v_booking.id, p_spots, null, v_now);
  exception when raise_exception then
    -- The court is closed that day or the slot is gone: skip this sample game.
    return;
  end;

  -- A rated sport gets the rating range its level range stands for.
  select rr.min_rating, rr.max_rating into v_min_rating, v_max_rating
  from app.rating_range(v_sport_id, '{}'::jsonb, p_min_level, p_max_level) rr;

  insert into public.games (
    id, sport_id, city_id, venue_id, host_id, booking_id, during, utc_offset_minutes,
    spots, min_level, max_level, min_rating, max_rating, price_per_player)
  values (
    p_game_id, v_sport_id, v_city_id, v_venue_id, p_players[1], v_booking.id, v_booking.during, v_offset,
    p_spots, p_min_level, p_max_level, v_min_rating, v_max_rating,
    round(v_booking.total_price::numeric / p_spots)::integer);

  insert into public.game_participants (game_id, user_id, joined_at)
  select p_game_id, t.user_id, v_now + t.position * interval '1 second'
  from unnest(p_players) with ordinality as t (user_id, position);
end $$;

select pg_temp.actra_seed_game(md5('actra:g1')::uuid, md5('actra:v1c1')::uuid, 1, 1140, 4, 2, 4, array[md5('actra:p1')::uuid, md5('actra:p2')::uuid]);
select pg_temp.actra_seed_game(md5('actra:g2')::uuid, md5('actra:v2c1')::uuid, 1, 1200, 10, 1, 5, array[md5('actra:p3')::uuid, md5('actra:p1')::uuid, md5('actra:p6')::uuid, md5('actra:p7')::uuid, md5('actra:p5')::uuid, md5('actra:p8')::uuid, md5('actra:p2')::uuid]);
select pg_temp.actra_seed_game(md5('actra:g3')::uuid, md5('actra:v3c1')::uuid, 2, 1110, 2, 3, 5, array[md5('actra:p4')::uuid]);
select pg_temp.actra_seed_game(md5('actra:g4')::uuid, md5('actra:v1c2')::uuid, 2, 1140, 4, 3, 5, array[md5('actra:p7')::uuid, md5('actra:p5')::uuid, md5('actra:p8')::uuid, md5('actra:p1')::uuid]);
select pg_temp.actra_seed_game(md5('actra:g5')::uuid, md5('actra:v4c1')::uuid, 1, 1050, 4, 2, 4, array[md5('actra:p5')::uuid, md5('actra:p8')::uuid, md5('actra:p2')::uuid]);
select pg_temp.actra_seed_game(md5('actra:g6')::uuid, md5('actra:v6c1')::uuid, 1, 1260, 10, 1, 5, array[md5('actra:p6')::uuid, md5('actra:p3')::uuid, md5('actra:p1')::uuid, md5('actra:p7')::uuid, md5('actra:p4')::uuid]);

drop function pg_temp.actra_seed_game(uuid, uuid, integer, integer, integer, integer, integer, uuid[]);

-- Each tournament summary (fees, places, places taken) becomes the real totals
-- of its categories and registrations.
select app.sync_tournament_summary(id) from public.tournaments
where id in (md5('actra:t1')::uuid, md5('actra:t2')::uuid, md5('actra:t3')::uuid);
