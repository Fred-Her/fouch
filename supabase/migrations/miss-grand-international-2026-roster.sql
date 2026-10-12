-- FOUCH 0.3B — Miss Grand International 2026 initial roster snapshot import.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET — awaiting founder approval
-- (see this sprint's Roster Import Gate report).
-- ============================================================
--
-- Source: https://missgrandinternational.com/contestants/profile/
-- Extracted directly from the official site's rendered DOM by the
-- founder (article.contestant-list-col / country-{slug} /
-- .contestant-name), on {TIMESTAMP TO BE FILLED AT ACTUAL RUN TIME}.
-- Not sourced from Wikipedia or any secondary source. See this
-- sprint's Roster Import Gate report for full validation (80 total,
-- 78 ACTIVE, 2 PENDING: Lebanon, Morocco — no duplicates, no empty
-- countries, Unicode/diacritics preserved verbatim from the DOM
-- snapshot).
--
-- Country slugs from the DOM are mapped explicitly to ISO 3166-1
-- alpha-2 country_code + a display country_name — never used as the
-- country_code directly. Kosovo uses XK (the common unofficial code
-- also used by country-flag-icons, the same package this codebase
-- already depends on for flag rendering — see CountryFlag.tsx, updated
-- in this same sprint to add every code this import needs).
--
-- IDEMPOTENCY: this is an INITIAL SNAPSHOT import, not a general-
-- purpose upsert tool. Re-running it exactly as-is is safe — the
-- ON CONFLICT clause below targets the existing partial unique index
-- (event_slug, country_code) WHERE status IN ('ACTIVE','PENDING') and
-- updates the SAME row in place (same id, same created_at), so a
-- second run of this exact file never creates a duplicate participant
-- or a false "replacement". This is NOT what a later real-world
-- replacement uses — see FOUCH_EVENT_PARTICIPANTS_IMPORT.md's
-- replace-a-participant workflow (§5), which deliberately creates a
-- NEW row with a NEW id and marks the old one REPLACED. Running this
-- snapshot file again after a real replacement has happened would
-- incorrectly overwrite the replacement back to this snapshot — this
-- file is for the one-time initial load only, not for ongoing
-- maintenance.
--
-- SAFETY: touches ONLY event_participants rows for
-- 'miss-grand-international-2026'. Does not reference, join, or
-- modify predictions, prediction_versions, prediction_items,
-- auth.users, or the events row itself (prediction_lock_at
-- untouched). Does not add or change any foreign key on
-- prediction_items.participant_id.

insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at, notes)
values
  ('miss-grand-international-2026', 'AL', 'Albania', 'SARA SHEHU', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: albania'),
  ('miss-grand-international-2026', 'AM', 'Armenia', 'AMEST ARUTIUNIAN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: armenia'),
  ('miss-grand-international-2026', 'AU', 'Australia', 'CAT JANE SHEPHERD', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: australia'),
  ('miss-grand-international-2026', 'BD', 'Bangladesh', 'ANONNA FATIMA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: bangladesh'),
  ('miss-grand-international-2026', 'BE', 'Belgium', 'EMILY BAESEN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: belgium'),
  ('miss-grand-international-2026', 'BO', 'Bolivia', 'KAITHLYN DA ROCHA FERREIRA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: bolivia'),
  ('miss-grand-international-2026', 'BR', 'Brazil', 'PAULA ASSUNÇÃO', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: brazil'),
  ('miss-grand-international-2026', 'CA', 'Canada', 'PATRICIA ROSALYN SEWARD', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: canada'),
  ('miss-grand-international-2026', 'CL', 'Chile', 'IGNACIA MICHELSON', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: chile'),
  ('miss-grand-international-2026', 'CN', 'China', 'LIU MENGMENG', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: china'),
  ('miss-grand-international-2026', 'CO', 'Colombia', 'MARÍA PAULA BERRIO', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: colombia'),
  ('miss-grand-international-2026', 'CR', 'Costa Rica', 'CATALINA MURILLO', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: costa-rica'),
  ('miss-grand-international-2026', 'CI', 'Côte d''Ivoire', 'MARLÈNE KANY KOUASSI', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: cote-divoire'),
  ('miss-grand-international-2026', 'CU', 'Cuba', 'ALYANNI T. GOMEZ', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: cuba'),
  ('miss-grand-international-2026', 'CZ', 'Czech Republic', 'HANA DĚDKOVÁ', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: czech-republic'),
  ('miss-grand-international-2026', 'DO', 'Dominican Republic', 'KEITTY FAMILIA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: dominican-republic'),
  ('miss-grand-international-2026', 'EC', 'Ecuador', 'SHYARE ANDRADE', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: ecuador'),
  ('miss-grand-international-2026', 'EG', 'Egypt', 'MENNA ELBATRAN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: egypt'),
  ('miss-grand-international-2026', 'SV', 'El Salvador', 'VALERIA AMAYA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: el-salvador'),
  ('miss-grand-international-2026', 'FR', 'France', 'AXELLE VARIN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: france'),
  ('miss-grand-international-2026', 'GE', 'Georgia', 'IOANNA SHERVASHIDZE', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: georgia'),
  ('miss-grand-international-2026', 'GH', 'Ghana', 'ADELAIDE SOMUAH TWUM', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: ghana'),
  ('miss-grand-international-2026', 'GT', 'Guatemala', 'XIMENA CARRILLO', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: guatemala'),
  ('miss-grand-international-2026', 'GY', 'Guyana', 'KHADESIA WALKER', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: guyana'),
  ('miss-grand-international-2026', 'HT', 'Haiti', 'ESTEPHANIE CHARLES', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: haiti'),
  ('miss-grand-international-2026', 'HN', 'Honduras', 'EMELY CARMELINA ALEMAN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: honduras'),
  ('miss-grand-international-2026', 'HK', 'Hong Kong', 'YOLANDA LIU XUEBIN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: hongkong'),
  ('miss-grand-international-2026', 'IN', 'India', 'LAKSHITA THILAGARAJ', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: india'),
  ('miss-grand-international-2026', 'ID', 'Indonesia', 'DILZA SALSABILA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: indonesia'),
  ('miss-grand-international-2026', 'IR', 'Iran', 'TANIN ALEMI', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: iran'),
  ('miss-grand-international-2026', 'IT', 'Italy', 'ANGELICA MARZIALI', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: italy'),
  ('miss-grand-international-2026', 'JM', 'Jamaica', 'SIMONE GARDNER', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: jamaica'),
  ('miss-grand-international-2026', 'JP', 'Japan', 'SARA CHIBA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: japan'),
  ('miss-grand-international-2026', 'KZ', 'Kazakhstan', 'ANEL YEMEL', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: kazakhstan'),
  ('miss-grand-international-2026', 'XK', 'Kosovo', 'ALBA FAZLIJA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: kosovo'),
  ('miss-grand-international-2026', 'LA', 'Laos', 'LOUISE CHANTHALANGSY', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: laos'),
  ('miss-grand-international-2026', 'LB', 'Lebanon', null, 'PENDING', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: lebanon'),
  ('miss-grand-international-2026', 'MO', 'Macau', 'MONIECE LAM MAN SI', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: macau'),
  ('miss-grand-international-2026', 'MY', 'Malaysia', 'VYAN TRISNI', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: malaysia'),
  ('miss-grand-international-2026', 'MT', 'Malta', 'NATALIA GALEA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: malta'),
  ('miss-grand-international-2026', 'MX', 'Mexico', 'PETY JUÁREZ', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: mexico'),
  ('miss-grand-international-2026', 'MD', 'Moldova', 'REGINA GANZENKO', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: moldova'),
  ('miss-grand-international-2026', 'MN', 'Mongolia', 'AMBER YUHAN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: mongolia'),
  ('miss-grand-international-2026', 'ME', 'Montenegro', 'ANDRIJANA DELIBASIC', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: montenegro'),
  ('miss-grand-international-2026', 'MA', 'Morocco', null, 'PENDING', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: morocco'),
  ('miss-grand-international-2026', 'MM', 'Myanmar', 'CHRISTINE', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: myanmar'),
  ('miss-grand-international-2026', 'NP', 'Nepal', 'SUMNIMA PURI', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: nepal'),
  ('miss-grand-international-2026', 'NL', 'Netherlands', 'BEAU MEGAN GOOS', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: netherlands'),
  ('miss-grand-international-2026', 'NZ', 'New Zealand', 'EMILY FAULKNER', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: new-zealand'),
  ('miss-grand-international-2026', 'NI', 'Nicaragua', 'NAHOMY HILL MARTINEZ', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: nicaragua'),
  ('miss-grand-international-2026', 'NG', 'Nigeria', 'UZOGHELI IFEOMA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: nigeria'),
  ('miss-grand-international-2026', 'NO', 'Norway', 'AYU ZHAFIRA KYNBRÅTEN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: norway'),
  ('miss-grand-international-2026', 'PK', 'Pakistan', 'ZARA YOUNUS', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: pakistan'),
  ('miss-grand-international-2026', 'PY', 'Paraguay', 'MICAELA VIVEROS', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: paraguay'),
  ('miss-grand-international-2026', 'PE', 'Peru', 'ZULIET SEMINARIO', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: peru'),
  ('miss-grand-international-2026', 'PH', 'Philippines', 'ANGELICA LOPEZ', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: philippines'),
  ('miss-grand-international-2026', 'PT', 'Portugal', 'MILENA FERNANDEZ RABELO', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: portugal'),
  ('miss-grand-international-2026', 'PR', 'Puerto Rico', 'VICKY CARBONEL', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: puerto-rico'),
  ('miss-grand-international-2026', 'RO', 'Romania', 'ANDREEA CIUCA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: romania'),
  ('miss-grand-international-2026', 'RU', 'Russia', 'POLINA AMMOSOVA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: russia'),
  ('miss-grand-international-2026', 'SL', 'Sierra Leone', 'ADEL CAROLINE JUSU', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: sierra-leone'),
  ('miss-grand-international-2026', 'SG', 'Singapore', 'NICOLE NISHA BACON', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: singapore'),
  ('miss-grand-international-2026', 'SK', 'Slovakia', 'VIKTÓRIA KLOKNEROVÁ', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: slovak-republic'),
  ('miss-grand-international-2026', 'ZA', 'South Africa', 'ESTÈE-MARI SMIT', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: south-africa'),
  ('miss-grand-international-2026', 'KR', 'South Korea', 'LANG SA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: south-korea'),
  ('miss-grand-international-2026', 'SS', 'South Sudan', 'AKOI AROK', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: south-sudan'),
  ('miss-grand-international-2026', 'ES', 'Spain', 'ALBA MARÍA RUIZ', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: spain'),
  ('miss-grand-international-2026', 'LK', 'Sri Lanka', 'NETHAKI LOKUGAMAGE', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: sri-lanka'),
  ('miss-grand-international-2026', 'CH', 'Switzerland', 'SARAH LOUISA ROHRER', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: switzerland'),
  ('miss-grand-international-2026', 'TW', 'Taiwan', 'YAN XINGXUE', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: taiwan'),
  ('miss-grand-international-2026', 'TZ', 'Tanzania', 'JIHAN MOHIN DIMACHK', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: tanzania'),
  ('miss-grand-international-2026', 'TH', 'Thailand', 'PATTHAMA JITSAWAT', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: thailand'),
  ('miss-grand-international-2026', 'GB', 'United Kingdom', 'POOJA GHODEKAR', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: united-kingdom'),
  ('miss-grand-international-2026', 'UY', 'Uruguay', 'FRANCIE MILLÁN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: uruguay'),
  ('miss-grand-international-2026', 'US', 'United States', 'VICTORIA OLUWAKOTANMI', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: usa'),
  ('miss-grand-international-2026', 'VI', 'U.S. Virgin Islands', 'BRI STERN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: us-virgin-islands'),
  ('miss-grand-international-2026', 'VE', 'Venezuela', 'LADY DI MOSQUERA', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: venezuela'),
  ('miss-grand-international-2026', 'VN', 'Vietnam', 'EMOURA PHẠM', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: vietnam'),
  ('miss-grand-international-2026', 'ZW', 'Zimbabwe', 'SHELLY USMAN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: zimbabwe'),
  ('miss-grand-international-2026', 'TR', 'Türkiye', 'RONIKA BAŞARAN', 'ACTIVE', 'https://missgrandinternational.com/contestants/profile/', now(), 'Initial 0.3B snapshot import — DOM slug: turkiye')
on conflict (event_slug, country_code) where status in ('ACTIVE', 'PENDING')
do update set
  contestant_name = excluded.contestant_name,
  status = excluded.status,
  source_url = excluded.source_url,
  source_checked_at = excluded.source_checked_at,
  notes = excluded.notes,
  updated_at = now();
