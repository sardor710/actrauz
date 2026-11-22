# Actra — Product Specification & Feature Plan

**Status:** Product design, approved for planning. The tech stack is out of scope and will be decided separately.
**Date:** 2026-11-19
**Audience:** The engineering, design and QA teams who will turn this into implementation plans.

> **How to read this document**
> - Decisions the founder made are written as plain requirements.
> - Defaults filled in during design are marked **[Proposal]**. They are sensible starting points the team may tune, not founder commitments.
> - **[Phase 1]** = launch. **[Phase 2]** = after launch (online payments, tournament brackets).
> - Open business questions that block nothing at the start are collected in §15.

---

## Contents

1. [Vision & Why](#1-vision--why)
2. [Goals, Non-Goals, Anti-Goals](#2-goals-non-goals-anti-goals)
3. [Markets, Languages, Currencies](#3-markets-languages-currencies)
4. [Roles & Permissions](#4-roles--permissions)
5. [Money Model (Hybrid)](#5-money-model-hybrid)
6. [Sports Model](#6-sports-model)
7. [Player App](#7-player-app)
8. [Skill Levels, Ratings & Reliability](#8-skill-levels-ratings--reliability)
9. [Games: Available Games, Game Requests, Teams](#9-games-available-games-game-requests-teams)
10. [Tournaments](#10-tournaments)
11. [Venue Owner Panel](#11-venue-owner-panel)
12. [Admin Panel](#12-admin-panel)
13. [Notifications (In-App)](#13-notifications-in-app)
14. [Core Entities & State Machines](#14-core-entities--state-machines)
15. [Open Business Questions](#15-open-business-questions)
16. [Rollout Approach](#16-rollout-approach)
17. [Decision Log](#17-decision-log)

---

## 1. Vision & Why

Actra is an all-in-one sports community and facility marketplace for **Uzbekistan and Kazakhstan**. It works like Playo (venue booking plus games) combined with Lunda Padel (skill-rated partner matching).

It connects recreational and competitive players with:
- **venues**, through real-time court booking
- **other players**, through games, game requests, teams and skill-based matching
- **tournaments**, through category-based registration

It also gives **venue owners** and **Actra administrators** one system for schedules, pricing, walk-in bookings and revenue.

**Why now:** the region has no dominant local equivalent. Players coordinate through Telegram groups and phone calls, and venues run their schedules on paper or in spreadsheets.

**What success looks like:**
- Players in Tashkent, Almaty and Astana use Actra by default to find a court or a game.
- Venues use the owner calendar as their single source of truth, including walk-in and phone bookings, not just app bookings.

## 2. Goals, Non-Goals, Anti-Goals

### Goals
- Instant self-serve booking of real-time court availability.
- An easy way to find people to play with at the right level.
- Venues get a calendar, pricing tools and analytics they actually use daily.
- Admins can run the whole platform (venues, owners, banners, tournaments, users) without engineering help.
- Four languages are fully supported from day one.

### Non-Goals (for now)
- **No in-app chat and no messaging-app integrations.** Coordination happens through game pages, notes and in-app notifications.
- **No online payments in Phase 1.** Players pay at the venue.
- **No tournament brackets, scheduling or scores in Phase 1.** Registration only.
- **No booking or payment for place-only sports** (gym, running, riding).
- **No gym memberships or passes sold through Actra.**

### Anti-Goals (failures even if the feature "works")
- **Double-booked slots.** An app booking and an owner's walk-in booking must never take the same slot.
- **Owners keep a paper schedule in parallel** because the calendar is slow or awkward. The owner calendar must be faster than paper.
- **Pay-at-venue gets abused** by players who book and don't show, eroding venue trust. Reliability rules exist to prevent this.
- **Untranslated or mixed-language screens** in any of the four languages.
- **Skill levels are meaningless** and matchmaking feels unfair.

## 3. Markets, Languages, Currencies

| City | Country | Currency | Phase 2 payment providers |
|---|---|---|---|
| Tashkent | Uzbekistan | UZS | Click, Payme |
| Almaty | Kazakhstan | KZT | Kaspi, Freedom |
| Astana | Kazakhstan | KZT | Kaspi, Freedom |

- **City is a first-class concept.** Every venue, game, game request, team, tournament and banner belongs to a city.
- The player's city is detected from their location. If location access is denied, they choose it manually, and they can switch it at any time.
- **Currency** follows the venue's or tournament's country. Prices are always shown in local currency, with no conversion.
- **Time:** all times are shown and stored in the venue's local time. Today that is UTC+5 for all three cities, but the system must not hard-code this.
- **Languages: Uzbek, Russian, Kazakh and English are all mandatory.**
  - Every UI string, system notification, email or bot message, and error is translated into all four.
  - Admin-entered content (venue descriptions, tournament titles and descriptions, banner header text, announcements, sport names) has a field per language.
  - **[Proposal]** If a translation is missing, the content falls back to Russian, then English.
  - The app language defaults to the device language if it is supported, otherwise Russian. It can be changed in the profile.
  - **[Proposal]** For Uzbek, support Latin script at launch. Cyrillic Uzbek is a later option.

## 4. Roles & Permissions

One account can hold several roles. For example, a venue owner also plays.

| Capability | Player | Venue Owner | Admin |
|---|---|---|---|
| Book courts, join or host games, register for tournaments | ✅ | ✅ | ✅ |
| View and edit **assigned** venues' details | — | ✅ | ✅ (all) |
| Edit **assigned** venues' courts (details, hours, pricing) | — | ✅ | ✅ (all) |
| Create or delete venues | — | ❌ | ✅ |
| Create, duplicate or delete courts | — | ❌ | ✅ |
| Owner calendar: add walk-in bookings, cancel bookings, mark paid or no-show | — | ✅ (assigned) | ✅ (all) |
| Owner dashboard (assigned venues) | — | ✅ | ✅ |
| Assign venue owners | — | ❌ | ✅ |
| Banners, tournaments, sports list, users, announcements, audit log | — | ❌ | ✅ |

- **[Proposal]** A venue can have **several owners**, e.g. an owner plus a manager. All of them have equal rights in Phase 1.
- **[Proposal]** Owners can **block slots** (maintenance or private events) without creating a booking. Blocked slots appear as unavailable to players.
- **[Proposal]** Admin sub-roles (super admin vs. content admin) are a later option. In Phase 1 there is one admin role.

## 5. Money Model (Hybrid)

### Phase 1: Pay at venue
- A player books in the app and chooses **"Pay at venue"** (cash or card on site). The booking is confirmed instantly.
- After the slot ends, the owner marks the booking **Paid** or **No-show** in the calendar.
  - "Paid" bookings drive the revenue figures on the owner and admin dashboards.
  - "No-show" lowers the player's reliability score (§8.3).
- **[Proposal]** If a booking is not marked within 48 hours after the slot, it is auto-marked **Completed (unverified)**. It counts toward booking numbers, and its revenue is shown separately as "unconfirmed".
- **How Actra earns** is an open business decision (§15): a per-booking fee or a monthly subscription. **[Proposal]** Start with a per-app-booking fee. The admin panel provides a **monthly billing report per venue**: the count of app bookings and the fee owed.
- Tournament entry fees are collected by the organizer or at the event, and the admin marks registrations **Paid**.

### Phase 2: Online payments
- At checkout, the player pays online through the providers for the venue's country (UZ: Click or Payme; KZ: Kaspi or Freedom). Pay-at-venue remains available per venue if the owner allows it.
- Actra collects the money, keeps a **commission**, and pays venues out on a schedule. Payouts and statements appear in the owner panel.
- **Cancellation and refund policy** applies. **[Proposal]** Full refund if cancelled more than 24 hours before the start, no refund after that. Venue-initiated cancellations are always fully refunded.
- Available Games: each joining player pays their share online when they join.
- Tournaments: the spot is confirmed only after successful payment.

### Design rule for Phase 1
Bookings, game joins and tournament registrations must carry a **payment status** and **payment method** from day one. Phase 2 must not require reworking these flows or the dashboards.

## 6. Sports Model

The admin manages the sports list; adding a sport needs no app release. Each sport has:
- a name in four languages, and an icon
- a **type**:
  - **Bookable:** has venues with courts or tee times, live availability and booking. Examples: tennis, football, padel, golf, badminton, pickleball.
  - **Place-only:** games happen at a place and time with **no booking and no payment**. Examples: gym, running, riding.
- a **rating mode**: *Simple level 1–5* or *Competitive rating 1.0–7.0* (padel and tennis). See §8.
- **[Proposal]** Default player count per game, e.g. padel 4, tennis 2 or 4, football 10 to 14.

How place-only sports work:
- **Gym:** the host picks a gym from the venue list. The assumption is that every participant already has a subscription or access there. Gym venues have profiles (contacts, hours, photos) but no slots.
- **Running:** the host drops a **meeting point on the map**, plus distance and pace. There is no venue.
- **Riding:** the host picks a place or stable from the venue list, or a map point.

## 7. Player App

### 7.1 Sign-up & sign-in
- **Primary: Telegram bot with phone sharing.**
  1. In the app or website, the user taps "Sign in with Telegram".
  2. They are deep-linked to the Actra bot with a one-time login token.
  3. The bot asks them to **share their contact**, which gives Actra a verified phone number.
  4. The app session is created and the user returns to the app.
- **The phone number is the account's identity.** It is unique per account.
- **Secondary: Google sign-in.** **[Proposal]** Google-only users must link a phone number through the Telegram bot before their first booking, game join or tournament registration, so every booking has a verifiable phone number.
- Email and password sign-in is dropped (§17).
- First sign-in collects:
  - full name
  - city
  - preferred language
  - sports played, with a level per sport (§8)
  - optional photo
  - **terms and privacy acceptance** (required)

### 7.2 Profile
- Name, photo and city.
- Per sport: level or rating (provisional or established), games played, and a leaderboard position for competitive sports.
- Reliability badge and sportsmanship score (§8).
- Teams the player belongs to.
- History: past bookings, games and tournaments.
- Settings: language, city, notification preferences, sign-out, **delete account**.

### 7.3 Home & discovery feed
The feed is city-scoped and ordered by distance when location access is granted. It has these sections:
1. **Promotional banners:** a carousel of active banners for the city (§12.4). Tapping one opens its URL.
2. **Game Requests:** nearby open requests with sport, time window, "X of Y interested" and level range.
3. **Available Games:** joinable games with sport, venue, time, spots left, level range and price per player.
4. **Available Courts:** venues with free slots **today and in the next few hours**, showing the next free slot times.
5. **Tournaments:** upcoming tournaments with registration open.

Each section has "See all", which opens a full list with filters. **[Proposal]** The feed is filtered by the player's selected sports by default, and a toggle shows all sports.

### 7.4 Venue discovery
- List and map views.
- Search by venue name.
- **Filters:** sport, city or district, distance, date and time with free slots, price range, amenities. **[Proposal]** Amenities include parking, showers, indoor/outdoor and lighting.

### 7.5 Venue profile
- Name, photos (optional, per venue and per court), address with map, phone (tap to call) and Instagram link.
- Sports offered, working hours per day, and a fee range per sport (min to max hourly price derived from the court pricing).
- Courts list, and for bookable sports a **live availability** entry point.
- For place-only venues (e.g. gyms): profile only, plus a "Create a game here" button.

### 7.6 Booking flow (bookable sports)
1. **Choose:** venue → sport → date. The app shows the courts for that sport with their slots for the date (§11.3 explains slot generation).
   - Free slots can be selected. Booked, blocked and past slots are disabled.
2. **Select:** one slot, or **several back-to-back slots on the same court**. The price is computed per slot from the court's price rules, as of the moment of booking.
3. **Hold:** on "Continue", the selected slots are **held** for this player so no one else can take them.
   - **[Proposal]** The hold lasts 5 minutes in Phase 1 and 10 minutes in Phase 2.
   - The hold is released when it expires or the player goes back.
4. **Summary and payment method:**
   - court, date, times and total price
   - payment method: Phase 1 is "Pay at venue"; Phase 2 adds the providers for the venue's country
   - number of players (optional) and a note
5. **Confirm:** the booking becomes **Confirmed** and the slot shows as booked in the app and in the owner calendar **at the same time**.
6. **After confirming:** the booking appears in "My bookings" with a "Create a game from this booking" option (§9.1), and the player gets a confirmation notification plus a reminder (§13).

**Booking rules**
- A slot can belong to only one active booking or hold. This is enforced at the moment of hold and confirm, across both app and owner bookings.
- Player cancellation in Phase 1:
  - **[Proposal]** Free until 6 hours before the start.
  - After that, it counts as a **late cancellation** and slightly lowers reliability.
  - Phase 2 adds the refund policy (§5).
- **[Proposal] Anti-abuse in Phase 1:** a player can hold at most **3 upcoming pay-at-venue bookings** at once. Players with low reliability are limited to 1, or must pay online in Phase 2.
- If the venue cancels, the player is notified and their reliability is not affected.
- Bookings can't be made for past slots. **[Proposal]** They can be made up to 14 days ahead; this is configurable per venue.

### 7.7 Partner matching
- **"Find players":** a searchable list of players filtered by sport, level range and city or district, with reliability shown.
- From a player's profile: **invite them to a game** you host, or to your team.
- There is no direct messaging. Contact happens through game invites, game pages and notifications.
- **[Proposal]** Players can opt out of appearing in "Find players" in privacy settings.

## 8. Skill Levels, Ratings & Reliability

### 8.1 Simple level (most sports)
- Five levels: **1 Beginner, 2 Novice, 3 Intermediate, 4 Advanced, 5 Pro**.
- The player self-selects a level per sport and can change it at any time.

### 8.2 Competitive rating (padel and tennis)
- The scale runs from **1.0 to 7.0**, in the style of Lunda and Playtomic.
- **Starting point:** a short self-assessment questionnaire sets the initial rating. It covers years played, frequency, competition experience and specific skill questions.
- **After each game:**
  - The host enters the score, and the other players confirm or dispute it.
  - **[Proposal]** If nobody disputes the score within 24 hours, it is confirmed automatically.
  - A disputed result doesn't change any ratings and is flagged for admin review.
- **Rating update:** an Elo-style calculation adjusts each player's rating by the result, the margin and the opponents' ratings. For doubles, the team's strength is the average of the partners.
- **[Proposal] Provisional period:** for a player's first ~10 rated games their rating moves faster and is labelled **"provisional"**. After that it stabilises.
- **Leaderboards** per sport, per city.
- Phase 2 tournament results also feed ratings.

### 8.3 Reliability score (all sports)
This score is separate from skill and is visible on the player's profile and on join requests.

| Event | Effect **[Proposal]** |
|---|---|
| Owner marks the booking a no-show | Large decrease |
| Players in the same game report a no-show (majority of participants) | Large decrease |
| Late cancellation of a booking or game spot | Small decrease |
| Game or booking completed as agreed | Small increase |

- **[Proposal]** The score is shown as a percentage or badge (e.g. "Reliable", "New", "Unreliable").
- **[Proposal]** Below a threshold, the player can't join games or make pay-at-venue bookings for N days.
- Hosts can see reliability before approving join requests.

### 8.4 Sportsmanship
- After a game, each participant can give the others a thumbs up or down. The aggregate shows on the profile.
- Reports of abusive behaviour go to an admin review queue. **[Proposal]**

## 9. Games: Available Games, Game Requests, Teams

### 9.1 Available Game (place and time already fixed)
**What it is:** the host has already secured the place, and others join instantly until the game is full.

**How hosting works:**
- **Bookable sports:** the host picks one of their existing bookings or books a court during setup (§7.6). A game is always linked to a real booking.
- **Gym and riding:** the host picks a venue from the list. There is no booking.
- **Running:** the host picks a map meeting point and enters distance and pace.

**Fields:**
- sport, date and time, place
- total spots, with the host counting as one
- level range
- visibility: **Public** (shown in discovery) or **Invite-only** (shared by link or invite)
- note, e.g. "bring white balls"

**Joining:**
- Players who meet the level range and reliability rules join with one tap.
- Players outside them can send a **join request**, which the host approves or declines.
- When all spots are filled, the game is **Full**, leaves discovery, and stays visible to participants.

**Cost:**
- Bookable sports show the court price split equally as "≈ X per player".
- Phase 1: everyone pays at the venue. Phase 2: each joining player pays their share online.
- Place-only sports have no cost.

**Leaving and changes:**
- A player can leave freely until the cutoff (**[Proposal]** 6 hours before the start). After that, it counts as a late cancellation. The spot reopens and the host is notified.
- The host can remove a participant, edit the note, or change the spots (not below the current participant count).
- When the host cancels, all participants are notified, and the host chooses whether to keep or cancel the court booking.

**After the game:** score entry for padel and tennis (§8.2), no-show reports and sportsmanship votes.

### 9.2 Game Request (no place booked yet)
**What it is:** a "looking for players" post with no court.

**Fields:**
- sport
- date with a time window (e.g. Saturday 18:00–21:00)
- area or district (or a preferred venue)
- players needed
- level range
- note

**Flow:**
1. Others tap **"I'm in"**. The poster sees the interested players with their level and reliability, and can remove any of them.
2. Once enough players are in, the poster **converts** the request:
   - **Bookable sports:** the poster picks a venue and slot from live availability and books it (§7.6).
   - **Place-only sports:** the poster picks the place.
3. The request becomes an **Available Game**. All interested players are added as participants and notified.

**Expiry:** **[Proposal]** The request expires when its time window passes without conversion, and interested players are notified.

### 9.3 Teams (all sports)
- A team is a **standing group**, such as a riding club, running crew or regular football group. It has a name, sport, city, logo and description, plus an open or approval-required join policy.
- Roles are **Captain** (creator; can manage members, edit the team and host team games) and **Member**.
- **Team games** are hosted by the captain as Available Games:
  - visible to members first
  - **[Proposal]** optionally opened to the public after a set time if spots remain
- Members are notified of new team games.

## 10. Tournaments

### 10.1 Phase 1: Registration
**Browsing:**
- List cards show the cover image, title, sport, city, dates, entry fee range and registration status.
- Filters: **date**, **sport**, **city** and **A–Z** sort.

**Detail page:**
- cover image, title, description, venue and dates
- registration deadline
- categories, e.g. Men's, Women's, Mixed, or a level band like 3.0–4.0. Each category has:
  - an entry fee
  - a slot cap
  - a live **"X of Y filled"** counter
  - a type: **Singles** or **Pairs**

**Registration rules:**
- A player picks a category and registers. **[Proposal]** The admin can set eligibility rules per category, such as gender or a rating range. These rules are checked but can be overridden by the admin.
- **Pairs categories:** the registrant invites a partner by phone number or Actra username.
  - The spot shows **Pending** until the partner accepts.
  - **[Proposal]** It expires after 48 hours if the partner doesn't accept.
  - Pending registrations don't count toward the cap until accepted. **[Proposal]**
- **Capacity control:** when a category reaches its cap it is **grayed out and registration is disabled**. If someone cancels, the spot reopens automatically.
- **[Proposal] Optional waitlist** per category: freed spots are offered to the waitlist in order with a time-limited claim.
- **Payment:**
  - Phase 1: the admin or organizer marks registrations **Paid**.
  - Phase 2: players pay online, and the spot is only confirmed after payment.
- Players can cancel their registration until the deadline. **[Proposal]**

### 10.2 Phase 2: Brackets & Results
- Draw generation per category: knockout, or groups then knockout.
- Match scheduling on the venue's courts. Those slots are **auto-blocked** in the owner calendar.
- Score entry by the admin or organizer, with a **live bracket** in the app.
- Padel and tennis results feed ratings.

## 11. Venue Owner Panel

The owner panel is used on the web, and on mobile for calendar actions. Owners see **only venues assigned to them by an admin**.

### 11.1 Owner dashboard
The owner can filter by venue and court. Metrics:
- **Bookings:** totals for **Today**, **Last 7 days** and **This month**, split into app bookings and walk-in/phone bookings.
- **Revenue:** the sum of bookings marked **Paid** in the period, in local currency. Unconfirmed revenue is shown separately (§5).
- **Daily average bookings** over the selected period.
- **Peak hours:** the slots or hours of the day with the most bookings, shown as a simple heatmap by day and hour. **[Proposal]**
- **[Proposal] Utilisation %:** booked slots ÷ available slots for the period.
- **[Proposal]** No-show count and rate.

### 11.2 Venue & court details (edit only)
- **Venue:** name and description (four languages), photos, address and map pin, phone, Instagram, amenities, working hours.
- **Court:**
  - name, sport, photos
  - indoor/outdoor and surface
  - **slot length** (60, 90 or 120 minutes)
  - working hours, pricing, and active/inactive
- Owners **cannot** create or delete venues or courts. That is admin only.

### 11.3 Working hours & slot generation
- **Venue working hours** are set per day of the week, e.g. Mon–Fri 07:00–23:00, Sat–Sun 08:00–22:00, or closed.
- **Courts inherit the venue hours by default.** The owner can **override per day of the week** for an individual court.
- **[Proposal]** Date-specific overrides cover holidays and special closures.
- **Slot generation:**
  - Slots for a court and date run **back to back with no gaps**, starting at opening time, each lasting the court's slot length.
  - A final slot that would end after closing is not offered.
  - Example: 07:00–23:00 with 90-minute slots gives 07:00, 08:30, 10:00 … 20:30 (the last slot ends at 22:00). A 22:00 slot would end at 23:30, so it is omitted.
- **Changing hours or slot length when bookings exist:** existing bookings stay valid. Conflicting bookings are flagged to the owner for manual handling, and new slots follow the new settings.

### 11.4 Dynamic price configurator
- Each court has a **base price per slot**.
- **Price rules** take the form *days of week + time range → price per slot*, e.g. Mon–Fri 18:00–23:00 → 250,000 UZS, or Sat–Sun all day → 300,000 UZS.
- A slot gets the price of the rule matching its **start time**. If no rule matches, it uses the base price.
- **[Proposal]** Overlapping rules for the same day are rejected when saved, so the price is never ambiguous.
- The price is **locked on the booking** at the moment it is confirmed. Later price changes don't affect existing bookings.
- The interface is a simple weekly grid or rule list showing a preview of the resulting prices.
- The venue's public "fee range" is derived from these prices.

### 11.5 Interactive weekly booking calendar
**Layout:**
- Opens to the **current week**.
- Columns are days, with dates. Rows are **only active operating hours**, following the court's slots.
- One court is shown at a time with a court switcher. **[Proposal]** If all of a venue's courts share a slot length, a multi-court view is also available.
- Previous and next week navigation, plus a "Today" button.

**Cell states:**
- 🟩 **Available (green):** tap to open the **new booking popup**.
- ⬜ **Booked (gray):** tap to open the **booking details popup**.
- **[Proposal]** ▒ **Blocked** (maintenance or private) and **Past** states.
- **[Proposal]** App bookings and walk-ins carry a small source marker.

**New booking popup** (walk-in or phone booking):
- Fields: **Name**, **Phone number**, **Number of players**, **Payment method** (Cash, Card, Transfer).
- **[Proposal]** The owner can extend the booking over consecutive slots.
- **[Proposal]** If the phone matches an Actra user, the booking is linked to their account and appears in their "My bookings".
- The booking is saved with the same conflict protection as app bookings (§7.6).

**Booking details popup:**
- Read-only booking info: name, phone, players, payment method and status, source (App or Walk-in), the linked game if any, and the price.
- Actions:
  - **Mark Paid** / **Mark No-show** (after the start time)
  - **Cancel booking**, which requires a confirmation dialog. On confirm, the slot is freed immediately, and if the booking came from the app the player (and any game participants) are notified.

## 12. Admin Panel

### 12.1 Admin dashboard
- **Users:**
  - total users
  - **active users** (**[Proposal]** signed in within the last 30 days)
  - **new registrations** for Today, Last 7 days and This month
  - all of the above filterable by city
- **Revenue:** total generated revenue, **split between Venues and Tournaments**, filterable by city, period and currency. UZS and KZT are always shown separately and never summed.
- **[Proposal]** Booking volume, games created and tournament registrations as secondary charts.

### 12.2 Venue & court management
- Full **create, edit and delete** for any venue or court, including sport type, city, and every field in §11.2.
- **Fast court creation:**
  - **Add from scratch**, or
  - **tap an existing court card → Duplicate**, which opens a pre-filled copy (sport, slot length, hours, pricing, photos) to edit and save.
- **[Proposal]** Deleting a venue or court with future bookings is blocked until those bookings are cancelled or moved. Deactivating is offered as an alternative.

### 12.3 Owner assignment
- **Search registered users** by name or phone, then **assign them as owners** of a specific venue. That grants the Owner role for that venue.
- Owners can be removed from a venue. The role is revoked when the user has no venues left.

### 12.4 Ad banner manager
- A banner requires an **image**, **header text** (four languages) and a **web URL**.
- **[Proposal]** Optional fields: target cities, start and end dates, display order, active toggle.
- Banners appear **at the same time on the main website and the mobile app home screen**.
- **[Proposal]** Impressions and clicks per banner.

### 12.5 Tournament manager
- Create and edit tournaments with: cover image, title and description (four languages), sport, city, venue, dates, registration deadline, and **categories** (name, singles or pairs, entry price, slot cap, eligibility).
- Participant management per category: view, export, remove, move between categories, mark paid, manage the waitlist.
- Filter all tournaments by **date, sport, city or A–Z**.
- Phase 2: brackets, scheduling and scores (§10.2).

### 12.6 Sports management
- Create and edit sports: names in four languages, icon, **type** (Bookable or Place-only), **rating mode** (Simple or Competitive) and default player count.

### 12.7 Platform governance
- **Users:**
  - search, view profile and history
  - change roles (Player, Owner, Admin)
  - change account status (Active, Suspended, Banned)
  - reset reliability, resolve disputed scores and reports
- **Audit log:** every admin and owner action that changes data is recorded with who, what, when, and before/after values. Examples: venue edits, price changes, booking cancellations, role changes, banner publishing.
- **Announcements:** platform-wide in-app notifications, targetable by city, role or sport, with text in four languages. They can be sent immediately or scheduled.
- **[Proposal] Billing report:** per venue per month, the app booking count and the fee owed (§5).

## 13. Notifications (In-App)

- Notifications appear **only inside the app**, in an inbox with an unread badge. **[Proposal]** Device push notifications are allowed as the delivery channel for these in-app notifications; there is no messaging-app delivery.
- **[Proposal]** The one exception is the Telegram bot, used only for the sign-in handshake (§7.1). The bot is not used for notifications.

| Trigger | Recipient |
|---|---|
| Booking confirmed, cancelled by venue, or reminder (**[Proposal]** 2 hours before) | Player |
| New app booking or cancellation on a venue | Owner(s) |
| Someone joined or left your game; join request received | Host |
| Join request approved or declined; game cancelled, changed or full; game reminder | Participants |
| "I'm in" on your request; request converted to a game; request expired | Poster / interested players |
| Score entered (confirm or dispute); rating updated | Padel and tennis participants |
| Invited to a game, team or tournament pair | Invitee |
| Tournament registration confirmed; pair partner accepted or declined; spot freed (waitlist); deadline reminder | Registrants |
| Team game posted | Team members |
| Admin announcement | Targeted users |

Each notification deep-links to the relevant screen. Players can mute categories in settings.

## 14. Core Entities & State Machines

This section is conceptual and contains no technology choices.

**Main entities:**
- User (phone, profile, language, city, roles, status)
- PlayerSportProfile (sport, level or rating, provisional flag, games count)
- Reliability
- City
- Sport
- Venue
- VenueOwnerAssignment
- Court
- WorkingHours (venue or court, per weekday, with overrides)
- PriceRule
- Slot (generated) and Block
- Booking (source: App or Walk-in; slots; price; payment method and status; linked user or guest name and phone)
- Game (type: Booked, Place-only or Map-point; linked booking; spots; level range; visibility; team)
- GameParticipant
- JoinRequest
- GameRequest
- RequestInterest
- MatchResult (score, confirmations, disputes)
- Team
- TeamMember
- Tournament
- TournamentCategory
- Registration (singles or pair, partner, status, payment)
- Banner
- Announcement
- Notification
- AuditLogEntry

**Booking lifecycle:**
```
Held ──(confirm)──▶ Confirmed ──(slot ends)──▶ Completed ─▶ Paid | No-show | Completed (unverified, after 48h)
  │                    │
  └─(timeout/back)─▶ Released
                       ├─(player cancels)─▶ Cancelled by player (late flag if inside cutoff)
                       └─(owner/admin cancels)─▶ Cancelled by venue
Phase 2 adds: Pending payment (between Held and Confirmed), Refunded.
```

**Game lifecycle:**
```
Open ─▶ Full ─▶ (start time) In progress ─▶ Finished ─▶ (padel/tennis) Result pending ─▶ Result confirmed | Disputed
  └──────────────▶ Cancelled (by host or because the underlying booking was cancelled)
```

**Game Request lifecycle:**
```
Open ─▶ Converted (becomes a Game) | Expired | Cancelled
```

**Tournament registration lifecycle:**
```
Pending partner (pairs only) ─▶ Registered ─▶ Paid ─▶ (Phase 2) Playing
        └─▶ Expired               └─▶ Cancelled / Removed
Waitlisted ─▶ Offered ─▶ Registered | Lapsed
```

**Integrity rules the system must guarantee:**
1. Each court slot has at most one active hold or booking, regardless of source (app or owner).
2. A category's confirmed registrations never exceed its cap.
3. A game's participants never exceed its spots.
4. Prices and fees are locked onto bookings and registrations when they are confirmed.
5. Every money-affecting or permission-affecting change is in the audit log.

## 15. Open Business Questions

These don't block design or Phase 1 engineering, but they need answers before launch or before Phase 2:
1. **Phase 1 venue fee:** per app booking or monthly subscription, and the amounts per country.
2. **Phase 2 commission rate**, payout frequency, and who bears provider fees.
3. **Final cancellation and refund windows** (proposed: 6 hours for free cancellation in Phase 1, 24 hours for a full refund in Phase 2).
4. **Main website scope:** a marketing site with banners and app links only, or full booking on web as well.
5. **Tournament organizers:** only Actra admins, or can venues or external organizers create tournaments too (which would need an "organizer" role)?
6. **Legal:** terms of service and privacy policy per country, including personal-data localisation requirements in Uzbekistan and Kazakhstan. These may affect where data is stored, which is a tech-stack decision.

## 16. Rollout Approach

Three options were considered:

| Option | What ships first | Trade-off |
|---|---|---|
| **A. Big bang** | Everything in this document, Phase 1, in all three cities | Longest time to launch; the largest venue onboarding effort at once; hard to learn what matters |
| **B. Booking first** | Venue booking plus the owner panel in Tashkent; games, ratings and tournaments added in later releases | Fastest to market and wins venue trust early, but the community side (what makes players return) arrives late |
| **C. Core loop in one city, then expand** *(recommended)* | Tashkent first with booking, the owner calendar, Available Games, Game Requests, simple levels, reliability and tournament registration. Then the Kazakhstan cities. Then competitive ratings and teams. Then Phase 2 payments and brackets | Launches the full player loop (book → host a game → fill it) on a manageable venue base. Requires discipline to hold back ratings and teams |

**Recommended milestone order (Option C):**
1. **Foundation:** cities, sports, the four languages, Telegram sign-in, roles, the admin panel for venues, courts, owners, banners and sports.
2. **Booking core:** slot generation, pricing, the player booking flow, the owner calendar (walk-ins, cancel, paid/no-show), and the owner dashboard. This is the first venue-facing pilot in Tashkent.
3. **Community core:** Available Games (all sport types), Game Requests, simple levels, reliability, the discovery feed, and in-app notifications. **This is the public launch in Tashkent.**
4. **Tournaments Phase 1:** categories, pairs, capacity control, the admin tournament manager, and the admin dashboard revenue split.
5. **Kazakhstan launch:** Almaty and Astana content, KZT, and Kazakh-language QA.
6. **Competitive layer:** padel and tennis ratings, score confirmation, leaderboards, teams, sportsmanship.
7. **Phase 2:** online payments (Click, Payme, Kaspi, Freedom), commission and payouts, refunds, and tournament brackets and results.

The engineering team may reorder these milestones; the dependencies between them are noted in each section.

## 17. Decision Log

| Decision | Made by |
|---|---|
| Hybrid money model: pay at venue first, online payments with commission later | Founder |
| Markets: Tashkent, Almaty, Astana | Founder |
| Uzbek, Russian, Kazakh and English are mandatory | Founder |
| Sign-in via Telegram bot phone sharing; Google kept as a secondary option | Founder (Google retention from the original spec) |
| Email and password sign-in dropped | Design call. It conflicts with phone-as-identity, and the founder chose Telegram as the sign-in method. Reinstate if needed |
| Payment providers: Click and Payme (UZ), Kaspi and Freedom (KZ) | Founder |
| No chat; notifications only in the app | Founder |
| Sports list includes tennis, football, padel, gym, running, golf, riding and more | Founder |
| Ratings: simple 1–5 for most sports, competitive 1.0–7.0 for padel and tennis | Founder (option C) |
| Available Game = place already secured; Game Request = looking for players, no court yet; both included | Founder |
| Bookable sports vs. place-only sports (gym, running, riding); golf is bookable | Founder |
| Teams for every sport | Design call (founder raised teams for riding) |
| Fixed slot length per court, back to back with no gaps; multi-slot bookings allowed | Founder |
| Tournaments: registration in Phase 1, brackets and results in Phase 2 | Founder (option C) |
| Pair registration for doubles categories | Design call |
| Everything marked **[Proposal]** | Design call, open to tuning by the team |

**Reference products:** Playo (venue booking, games, discovery), Lunda Padel (skill-rated partner matching and club CRM), Playtomic (padel rating model).
