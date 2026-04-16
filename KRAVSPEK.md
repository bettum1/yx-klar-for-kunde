# Kravspesifikasjon: Klar for Kunde v2
## YX Norge AS — Produksjonsversjon

**Dokument:** Kravspek KfK v2
**Dato:** 17. april 2026
**Eier:** Alexander Bettum
**Status:** Arbeidsdokument

---

## 1. Produktvisjon

Klar for Kunde er et mobilt sparringsverktøy for YX Norges 273 stasjoner. Det erstatter papirbaserte RFC-skjemaer med en digital plattform som kombinerer selvevaluering, coaching-besøk, kampanjeoppfølging og HMS-årshjul — alt strukturert rundt kundereisen.

Appen er et coaching-verktøy, ikke et kontrollverktøy. YX er en selveierkjede. Stasjonslederne er entreprenører, ikke ansatte. Verktøyet skal bygge kompetanse og stolthet, ikke frykt.

Kjernefeature som skiller Klar for Kunde fra alle kommersielle alternativer (Zenput, SafetyCulture, Bindy, YOOBIC): **dual evaluering med persepsjonsgap-visualisering** — stasjonsleder vurderer seg selv, regionsjef vurderer ved besøk, gapet mellom de to driver samtalen.

---

## 2. Arkitektur

### 2.1 Tech-stack

| Komponent | Valg | Begrunnelse |
|-----------|------|-------------|
| Frontend | React SPA (Vite) | Eksisterende kompetanse, én kodebase |
| Hosting frontend | Vercel eller Cloudflare Pages | Gratis, custom domain, auto-deploy fra GitHub |
| Backend/Database | Supabase | Auth + PostgreSQL + REST API + Realtime. Gratis tier dekker 273 stasjoner |
| Bildelagring | Supabase Storage | Integrert med auth, 1GB gratis |
| DNS | Domeneshop (Alexanders domene) | CNAME til Vercel/Cloudflare |

### 2.2 Database-skjema (Supabase/PostgreSQL)

**stations** — 273 rader, importert fra Excel
- id (uuid, PK)
- name (text) — "YX Tønsberg"
- address (text)
- postnr (text)
- poststed (text)
- lat (float) — geocodet fra adresse
- lng (float)
- type (enum: fullservice | automat)
- forhandler (text) — eierens navn
- mobil (text)
- selskap (text)
- region_id (uuid, FK → regions)

**regions**
- id (uuid, PK)
- name (text) — "Vestfold", "Trøndelag", etc.
- regionssjef_id (uuid, FK → users)

**users**
- id (uuid, PK, Supabase Auth)
- name (text)
- email (text)
- role (enum: stasjonsleder | regionssjef | leder)
- station_id (uuid, FK → stations, nullable) — for stasjonsledere
- region_id (uuid, FK → regions, nullable) — for regionssjefer

**visits** — kjernetabellen
- id (uuid, PK)
- station_id (uuid, FK → stations)
- user_id (uuid, FK → users)
- role (enum: sl | rs) — hvilken rolle utførte besøket
- date (timestamptz)
- scores (jsonb) — {item_id: score_value}
- na_items (jsonb) — [item_ids markert N/A]
- notes (jsonb) — {item_id: "notat"}
- visit_note (text) — generell oppsummering
- total_score (int)
- max_score (int)
- pct (int)
- status (enum: draft | completed)

**visit_photos**
- id (uuid, PK)
- visit_id (uuid, FK → visits)
- item_id (int) — sjekkpunkt
- storage_path (text) — Supabase Storage path
- captured_at (timestamptz)
- lat (float)
- lng (float)

**actions** — avvik og tiltak
- id (uuid, PK)
- visit_id (uuid, FK → visits)
- station_id (uuid, FK → stations)
- item_id (int) — sjekkpunkt
- description (text)
- assigned_to (enum: stasjon | regionssjef | drift)
- due_date (date)
- status (enum: open | in_progress | completed | overdue)
- completed_at (timestamptz)
- completed_by (uuid, FK → users)
- evidence_photo (text) — storage path
- created_by (uuid, FK → users)

**hms_checks**
- id (uuid, PK)
- station_id (uuid, FK → stations)
- tertial (enum: t1 | t2 | t3)
- item_id (text) — h1, h2, etc.
- checked (boolean)
- checked_by (uuid, FK → users)
- checked_at (timestamptz)
- year (int)

### 2.3 Row Level Security (RLS)

Supabase RLS policies:
- **Stasjonsleder** ser kun egen stasjon (station_id = users.station_id)
- **Regionssjef** ser alle stasjoner i sin region (station.region_id = users.region_id)
- **Leder** ser alt
- Visits: bruker kan opprette, kun se egne + relaterte til sin stasjon/region
- Actions: stasjon ser egne, RS ser regionens, leder ser alle

### 2.4 Autentisering

Supabase Auth med e-post/passord.

**Førstegangsoppsett (MVP):**
- Forhåndsopprettede brukere for alle 273 stasjonsledere + regionssjefer
- Stasjonsleder logger inn med e-post + passord (sendt individuelt)
- Regionssjef logger inn med e-post + passord
- Leder logger inn med e-post + passord
- Ingen selvregistrering — admin oppretter brukere

**Innloggingsside:**
- YX-logo, "Klar for Kunde", e-post + passord
- "Husk meg" checkbox (persistent session)
- Rolle vises etter innlogging basert på user.role

---

## 3. Brukerroller og tilgang

### 3.1 Stasjonsleder (SL)

**Ser:**
- Kun egen stasjon
- Selvevalueringsskjema (RFC-sjekklisten)
- Historikk over egne selvevalueringer
- Historikk over regionsjefens besøk på stasjonen
- Feedback og tiltak fra regionssjef
- Åpne avvik/tiltak med status og frist
- HMS årshjul for egen stasjon
- Gjeldende kampanjeinformasjon

**Kan:**
- Fylle ut selvevaluering
- Registrere at HMS-punkter er gjennomført
- Oppdatere status på tiltak (markere som fullført med bevis-foto)
- Se referansebilder fra kundereisen
- Ta bilder og legge til notater

### 3.2 Regionssjef (RS)

**Ser:**
- Alle stasjoner i sin region
- Stasjonens siste selvevaluering (med scores per punkt)
- Gap-analyse mellom stasjonens og egen vurdering
- Historikk over egne besøk per stasjon
- Oversikt over alle åpne avvik/tiltak i regionen
- HMS-status per stasjon
- Kampanjeinformasjon

**Kan:**
- Gjennomføre coaching-besøk (RFC-sjekkliste)
- Se stasjonens vurdering ved siden av hvert punkt
- Opprette tiltak/avvik med ansvarlig, frist og beskrivelse
- Legge til notater, bilder og lydnotater
- Velge nærmeste stasjon basert på GPS
- Se coaching talking points per sjekkpunkt

### 3.3 Leder (Dashboard)

**Ser:**
- Alle stasjoner, alle regioner
- Nettverksoversikt med scorer
- Gap-analyse per stasjon (selvevaluering vs. RS-score)
- Kalibreringscore per stasjonsleder (gap over tid)
- Åpne avvik på tvers
- HMS-årshjulstatus for alle stasjoner
- Kampanjegjennomføringsrate
- Trend over tid

---

## 4. Funksjonelle krav

### 4.1 RFC-inspeksjon (kundereisestruktur)

**4 kategorier som følger kundereisen:**
1. Ankomst & synlighet (9 punkter, maks 29)
2. Tanking & betaling (8 punkter, maks 19)
3. Inn i butikken (19 punkter, maks 39)
4. Møtet med oss (3 punkter, maks 15)

**Scoring per punkt:** 3 valg + N/A
- Ikke godkjent (0 poeng) — rød
- Delvis (halvparten av maks, avrundet) — gul
- Godkjent (maks poeng) — grønn
- Ikke aktuell — ekskludert fra teller og nevner

**N/A-håndtering:** Punkt markert N/A fjernes fra totalscoren. Prosent beregnes som score / (maks − N/A-maks) × 100.

**Per sjekkpunkt, tilgjengelig:**
- Score-knapper (3 + N/A)
- Notatfelt med tale-til-tekst
- Kamera/bildeopplasting (flere bilder per punkt)
- Coaching talking point (kun synlig for RS)
- Stasjonens egenvurdering (kun synlig for RS)
- Gap-indikator ved avvik mellom SL og RS score
- Mulighet for å opprette tiltak direkte fra punktet

**Referansebilder:** Hver kategori har en kollapserbar seksjon med illustrasjon fra YX kundereise-dokumentet som viser hvordan det skal se ut.

**Kampanjereferanse:** Butikk-kategorien har en kollapserbar kampanjeoversikt med gjeldende K-periode, produkter, priser og plasseringsinstruksjoner.

### 4.2 Dual evaluering og gap-analyse

**Stasjonslederens selvevaluering:**
- Fylles ut uavhengig av RS-besøk (ideelt 24–48 timer før)
- Samme sjekkliste, samme scoringsmodell
- Synlig for stasjonen som "min vurdering"

**Regionsjefens besøk:**
- Under inspeksjon vises stasjonens siste selvevaluering per punkt i en blå boks
- Etter scoring vises gap-varsel: "⚠️ Gap: stasjonen sier Godkjent, du sier Delvis"
- Ferdig-skjermen viser begge scorer og gap i prosentpoeng

**Leder-dashboard:**
- Per stasjon: SL-score og RS-score side om side
- Gap i prosentpoeng
- Kalibreringscore: gjennomsnittlig gap over siste 6 besøk per stasjon
- Stasjoner med økende gap flagges

### 4.3 Tiltak og avviksoppfølging

**Opprettelse:**
- RS kan opprette tiltak direkte fra et sjekkpunkt under inspeksjon
- Felter: beskrivelse, ansvarlig (stasjon / RS / drift), frist, prioritet
- Foto kan legges ved

**Livssyklus:** Opprettet → Åpen → Under arbeid → Fullført (med bevis) / Forfalt → Eskalert

**Synlighet:**
- SL ser tiltak for sin stasjon med status og frist
- RS ser alle tiltak i sin region, sortert etter frist/status
- Leder ser alle tiltak, kan filtrere på region/stasjon/status

**Lukking:** Tiltak lukkes kun med bevis (foto/notat). Automatisk eskalering ved overskrift frist (konfigureres, f.eks. 7 dager).

### 4.4 HMS Årshjul

**Struktur:** 3 tertialer, 19 HMS-punkter fordelt (7+6+6), basert på eksisterende HMS-årshjul fra YX.

**Funksjon:**
- Tilgjengelig for begge roller
- Per stasjon, per år
- Hvert punkt kan sjekkes av med dato og bruker
- Gjeldende tertial markert visuelt
- Fremdriftsindikator per tertial

### 4.5 Kampanjemodul

**Gjeldende kampanje:** Vises som kollapserbar seksjon i Butikk-kategorien under inspeksjon.

**Innhold per kampanje:**
- Kampanjenavn og periode (K-5, uke 17–20)
- Produkter med priser
- Plassering (referanse til stasjonskartet)
- Bestillingsinformasjon
- Type (A-kampanje/B-kampanje/frivillig)

**Oppdatering:** Kampanjedata lagres som JSON i Supabase. Admin kan oppdatere via et enkelt admin-grensesnitt eller direkte i databasen. Ny kampanjeperiode = ny JSON-rad.

### 4.6 Tale-til-tekst

**Implementering:** Web Speech API (webkitSpeechRecognition) med `lang: "nb-NO"`.

**Fallback:** Hvis nettleseren ikke støtter Web Speech API (eldre Safari), vis melding: "Trykk mikrofon-ikonet på tastaturet for diktering" (iOS har innebygd diktering i tastaturet).

**UX:** Mikrofon-ikon ved hvert notatfelt. Trykk for å starte, trykk igjen for å stoppe. Tekst legges til i notatfeltet (append, ikke overskriv). Rød pulserende indikator under opptak.

### 4.7 Responsivt design

**Primær:** Mobiltelefon (iPhone/Android), portrett
**Sekundær:** iPad/nettbrett, liggende og stående
**Tertiær:** Desktop (for dashboard/admin)

**Krav:**
- Viewport-tilpasning: fungerer fra 375px til 1024px+
- Liggende modus på iPad: to-kolonne layout der det gir mening
- Touch-targets: minimum 48px (56px for utendørs glove-friendly bruk)
- Skriftstørrelse: minimum 14px for innhold, 16px i inputfelter
- YX Rød (#CF122D), YX Mørk blå (#0C2340) som primærfarger
- Inter som font (FF Clan for produksjonsversjon med lisens)

### 4.8 Nærmeste stasjon (geolokasjon)

**Funksjon:** Ved stasjonsliste for RS, sorter etter avstand fra brukerens posisjon.

**Implementering:** Browser Geolocation API → beregn avstand til alle stasjoner med geocodede koordinater (lat/lng importert fra adresse) → sorter.

**Krav:** Alle 273 stasjoner geocodes ved import (én gang, fra adresse via Google/Nominatim API).

---

## 5. Data-import

### 5.1 Stasjonsliste

Kilde: `2026_Distribusjonsliste_klistremerker_fullservice_og_automat.xlsx`

273 stasjoner med felter:
- Forhandler (eier)
- Navn (stasjonsnavn, inkl. "automat" for automater)
- Adresse, postnr, poststed
- Mobiltelefon
- Selskap (AS-navn)

**Import-steg:**
1. Parse Excel → JSON
2. Geocode alle adresser (lat/lng)
3. Tilordne regioner (manuelt eller basert på postnr/fylke)
4. Opprett Supabase-rader
5. Opprett stasjonsleder-brukere (en per stasjon, e-post basert på kontaktinfo)

### 5.2 Sjekkliste

Basert på Lars-Børges RFC-skjema, modernisert til YX-språk, strukturert som kundereise.

4 kategorier, 39 sjekkpunkter (etter fjerning av backoffice-punkter 10–13 og duplikat toalett).

### 5.3 HMS-punkter

19 punkter fordelt på 3 tertialer, basert på eksisterende HMS-årshjul.

### 5.4 Kampanjedata

K-5 (uke 17–20) som første datasett. 11 kampanjelinjer med produkter, priser, plassering.

---

## 6. Ikke-funksjonelle krav

### 6.1 Ytelse
- Førstegangsinnlasting: under 3 sekunder på 4G
- Inspeksjonsflyt: ingen ventetid mellom kategorier
- Bildeoppslasting: komprimeres til maks 200KB ved capture

### 6.2 Sikkerhet
- Supabase Auth med e-post/passord
- RLS på alle tabeller — stasjonsleder ser kun egen data
- HTTPS-only
- Bildemetadata strippet for personvern (beholder kun GPS/tid)

### 6.3 Tilgjengelighet
- WCAG AA minimum (AAA for utendørs bruk)
- Kontrast: 4.5:1 på alle tekstelementer
- Fungerer i Safari iOS 16+, Chrome Android, Chrome desktop

### 6.4 Merkevare
- YX-logo (fra logopakke, RGB-versjon for lys bakgrunn, hvit for mørk)
- Farger: YX Rød #CF122D, YX Mørk blå #0C2340, YX Blå #0B326B, YX Grå #D0D1D2
- Pay-off: "Din stasjon." på splash
- Font: Inter (web) / FF Clan (produksjon med lisens)

---

## 7. Milepæler

### v2.0 — MVP Produksjon (mål: uke 17–18)
- [ ] Supabase oppsett (auth, database, storage)
- [ ] Import av 273 stasjoner med geocoding
- [ ] Innlogging (e-post/passord)
- [ ] RFC-inspeksjon med 3 scorer + N/A
- [ ] Dual evaluering med gap-visning
- [ ] Foto per sjekkpunkt
- [ ] Tale-til-tekst i notatfelt
- [ ] Responsivt design (mobil + iPad)
- [ ] Nærmeste stasjon (GPS-sortering)
- [ ] Dashboard for leder
- [ ] Deploy på custom domene

### v2.1 — Tiltak og HMS (mål: uke 19–20)
- [ ] Tiltak/avvik med livssyklus
- [ ] HMS årshjul med tertialstruktur
- [ ] Kampanjemodul med K-periode data
- [ ] Eksport av besøksrapport (PDF)
- [ ] Push-varsler for forfalt tiltak

### v2.2 — Analytics og AI (mål: uke 21–24)
- [ ] Kalibreringscore per stasjon
- [ ] Trend-analyse over tid
- [ ] AI-generert besøksoppsummering
- [ ] AI-foreslåtte coaching-spørsmål
- [ ] Power BI-eksport

### Fremtidig (backlog)
- [ ] Offline-first med sync
- [ ] PWA installasjon
- [ ] Kampanjefoto-verifisering med AI
- [ ] Qlik-integrasjon for KPI-er per stasjon
- [ ] EcoOnline/Landax-integrasjon for HMS
- [ ] Automatisk eskalering ved kritiske funn

---

## 8. Åpne spørsmål

1. **Regionsinndeling:** Hvilke stasjoner tilhører hvilken region/regionssjef? Finnes det en masterliste?
2. **Stasjonsleder e-post:** Har alle stasjonsledere e-postadresser, eller brukes mobilnummer?
3. **Kampanjeoppdatering:** Hvem oppdaterer kampanjedata mellom K-periodene? Admin-grensesnitt, eller manuelt i database?
4. **Rebranding:** 45 stasjoner heter fortsatt "Best". Skal disse vises som "YX" i appen, eller beholde nåværende navn?
5. **Automat-stasjoner:** Har automater forenklet sjekkliste, eller full RFC?

---

*Dokumentet oppdateres løpende. Siste versjon i GitHub-repo.*
