# ContestDB × "The Guild" — Stitch Design Brief

> **What this is.** A paste-ready prompt pack for **Google Stitch** to design ContestDB in the
> *antique artisan's-ledger* theme from the reference ("The Guild"): parchment grounds, ink-black
> + burgundy, brass/gold dashed rules, high-contrast serif display, letterpress/engraving texture,
> and wax-seal motifs. It ships with **two themes and a toggle** (Parchment ☼ / Midnight Ledger ☾).
>
> **How to use it with Stitch.**
> 1. Paste **§2 Design System** first (this teaches Stitch the whole visual language + both themes).
> 2. Then paste **one screen prompt at a time** from **§3**. Each screen starts with a one-line
>    *Style anchor* — keep it, so the look stays consistent across screens.
> 3. **§4** has component prompts you can request individually; **§5** is the vocabulary/microcopy
>    so the copy stays in-world; **§6** lists exact color/type tokens.
> 4. Ask Stitch for **both a light and dark variant** of each screen, and include the theme toggle.
>
> Everything uses ContestDB's *real* domain (Max Speed Run, the Accumulator Math Quiz, the
> scoreboard freeze, verdicts like ACCEPTED/TLE, roles, the async judge) so Stitch produces
> on-topic content — not generic filler.

---

## 1. The product, in one paragraph (context for Stitch)

ContestDB is a platform to **host, run, judge and rank contests of any kind** — competitive
programming, robotics time-trials, chess, quizzes, writing, calligraphy. Its signature mechanic is
a **scoreboard freeze**: near the end, public standings are *sealed* while hosts still see the live
board. Submissions are a flexible payload that flows through an **asynchronous judge**
(Pending → Judging → Verdict). Users have a **per-contest role**: Host, Moderator, or Participant.
The Guild reskins this as a centuries-old **artisans' guild** that issues *commissions*, receives
*entries*, and keeps sealed *ledgers* of standing. Keep it elegant and editorial — a printed
guild register brought to the screen — never cartoonish "medieval."

**Domain → Guild lexicon** (use these words in the UI):

| ContestDB concept | Guild term to show |
|---|---|
| Contest / challenge | **Commission** (a.k.a. Challenge / Ledger) |
| Task within a contest | **Trial** or **Prompt** |
| Submission | **Entry** |
| Leaderboard / standings | **The Standing** / **Roll of Masters** |
| Scoreboard freeze | **The Seal** — "Standings sealed" (wax-seal icon) |
| Verdict (ACCEPTED/WA/TLE…) | **Verdict stamp** (ink stamp) |
| Prize / bounty | **Bounty** · currency **Cr** |
| Role: Host / Moderator / Participant | **Guildmaster** / **Warden** / **Artisan** |
| Host/admin console | **The Guild Hall** (management) |
| Enroll | **Enlist** |
| Invitation code | **Passphrase / Seal** |
| Announcement | **Proclamation** |
| Kick / ban | **Struck from the rolls** |
| Contest status PENDING_APPROVAL / ACTIVE / COMPLETED | **Unsealed** / **Open** / **Closed** |
| Judge worker deliberating | **The Jury deliberates** |
| Activity heatmap | **Ledger of Labour** |

---

## 2. Design System  *(paste this into Stitch FIRST)*

**Design a design system called "The Guild" — an antique artisan's-ledger / letterpress aesthetic
for a contest-hosting web app. Editorial, printed-register feel: parchment paper, ink, brass rules,
wax seals, engraving illustrations. Refined and elegant, not kitsch medieval. Provide TWO themes
with a visible toggle in the top navigation.**

### Themes
- **Parchment (light, default):** warm cream paper ground, near-black ink text, deep burgundy
  accent, brass/gold hairline + dashed rules, aged-manila cards.
- **Midnight Ledger (dark):** deep espresso-ink ground, aged off-white text, brightened
  vermilion accent, warm brass accents, dark-leather cards.
- **Toggle:** a small control at the right of the nav that flips a **sun ☼ / moon ☾** (or a lit
  lantern) between *Parchment* and *Midnight Ledger*. Persist the choice. Both themes must be
  equally finished — do not simply invert; re-tune contrast and keep the accent legible on both.

### Color tokens (see §6 for exact hex, in both themes)
Ground · Card/manila · Raised · Ink (text) · Muted ink · **Burgundy accent** · **Brass/gold rule**
· Deep "guild-green" (used for one feature card & dark surfaces) · Verdict semantics
(Accepted = ink-green, Rejected = burgundy-red, Timed-out = ochre, Pending = slate-blue).
Semantic verdict colors are separate from the burgundy brand accent.

### Typography
- **Display serif** (titles, commission names): a high-contrast Didone/Scotch serif — e.g.
  *Playfair Display* or *Libre Caslon Display*, heavy weight, tight tracking. This carries the page.
- **Body serif** (descriptions, prose): a readable book serif — e.g. *Lora* or *Source Serif 4*.
- **Label caps** (eyebrows, categories, metadata): letter-spaced **UPPERCASE small caps**, e.g.
  *Playfair* or a spaced *IBM Plex Serif*; tracking ~0.12em.
- **Ledger data / mono** (scores, ranks, Cr amounts, verdict codes, schema keys, timers):
  a typewriter monospace with tabular figures — e.g. *JetBrains Mono* or *Courier Prime* — to
  read like typed ledger entries. Always tabular-nums where numbers align.

### Texture & motifs (use tastefully, not everywhere)
- Subtle **paper grain** on the ground; faint **letterpress emboss** on headings.
- **Brass hairline rules** and **gold dashed dividers** between sections.
- **Wax-seal** device for the freeze/seal state and for "featured/verified" marks.
- **Engraving/etching** illustrations (sepia line-art) for commission thumbnails.
- **Illuminated drop-cap** on the featured commission's description.
- **Ink-stamp** treatment for verdicts (slightly rotated, distressed edges).
- **Corner flourishes** and small filigree only on hero/featured elements.
- **Ledger-line** backgrounds (faint horizontal rules) behind tables/standings.

### Iconography
Fine **line-engraving** icons (1px), warm ink color: quill, compass, gear, wax seal, scroll,
scales (judging), hourglass (timer), key (passphrase), laurel (rank). No filled/rounded modern icons.

### Component library (define these once)
1. **Top nav** — emblem + wordmark ("ContestDB / The Guild"), centered links (Explore, My Entries,
   Judging Panel, Leaderboard), right side: a **role pill** (e.g. "Guild"/avatar) + **theme toggle** + avatar.
2. **Segmented tab** — filled ink pill (active) with a small **burgundy count badge**, outlined pill (inactive).
3. **Commission card (3 variants):**
   - *Featured*: large, thin brass border, engraving thumbnail, "LIVE: 48H REMAINING" with red dot,
     black "FEATURED" tag, big serif title, description with drop-cap, dashed rule, **BOUNTY / 500 Cr**,
     avatar stack "+42".
   - *Standard (manila)*: bordered category chip, line icon top-right, serif title, 2-line description,
     hairline rule, "Prize:" + status ("Starts in 3 Days" / "Voting Closes Today").
   - *Dark (guild-green)*: dark surface, category eyebrow, muted-sage title, a **progress/seal meter**
     ("75% Capacity"), a geometric engraving mark.
4. **Status pills / verdict stamps** — Open (green dot), Sealed (wax icon), Closed (grey), and ink-stamp
   verdicts (ACCEPTED, WRONG_ANSWER, TLE, PENDING).
5. **Sealed-standings table** — ledger-lined rows, rank medallions (gold/silver/bronze laurel) for top 3,
   monospace scores, the viewer's own row highlighted; a **wax-seal banner** when frozen.
6. **Dashed section divider** with centered small-caps label ("END OF CURRENTLY DISPLAYED LEDGERS").
7. **Outline button with flourish glyph** ("RETRIEVE MORE ARCHIVES ⤿").
8. **Footer** — tan/brass band: wordmark + tagline, columns (Project Info: Manifesto, Terms, Privacy
   Parchment · Connect: Contact the Scribe, Community Hall, Newsletter), "© 2024 … All Rights Engraved."
9. **Modal / dialog** — parchment sheet with brass border and a wax-seal close button.
10. **Form fields** — underlined "ledger entry" inputs; labels in small caps; a red seal on invalid.
11. **Theme toggle** (as above).

### States to always include
Loading (a slowly-rotating brass compass/seal), empty ("The ledger is empty"), error (a red wax
"Rejected" seal), disabled, hover (ink underline / slight lift), focus (brass ring).

### Accessibility
WCAG-AA contrast in **both** themes; visible keyboard focus (brass ring); verdict never by color
alone (always paired with its stamped label); respect reduced-motion.

---

## 3. Screen prompts  *(paste one at a time; keep the Style anchor line)*

> **Style anchor (prepend to every screen):** *"The Guild" antique artisan-ledger theme — parchment
> ground, ink + burgundy + brass, high-contrast serif display (Playfair), typewriter-mono for data,
> wax-seal & engraving motifs; include the Parchment/Midnight theme toggle in the nav; give me light
> and dark variants.*

### 3.1 Landing / Guild Hall (guests)
Design a marketing landing page for guests. Top nav (emblem + "ContestDB — The Guild", links,
Sign in / Enlist buttons, theme toggle). **Hero**: a large illuminated headline "Run any contest.
Sealed in the ledger." with a letterpress feel and an illuminated drop-cap; a subtitle explaining
the guild hosts, judges and ranks commissions of every craft with the scoring engine kept in the
ledger itself; two buttons — "Enlist" (filled ink) and "Enter the Hall" (outline). Beside the hero,
a **framed engraving** and a small **sealed-standings preview card** ("Max Speed Run", a wax-seal
"Standings sealed" ribbon, top three: satil 92 / sayma 90 / nondiny 85 with laurel ranks).
Below: a row of four **feature plates** (engraving icon + title) — "A ledger-native engine",
"Any craft, any commission", "The Seal (scoreboard freeze)", "An impartial jury (async judging)".
A closing band with a verse-like CTA "Take up the quill" and the guild footer. Elegant, editorial,
lots of parchment whitespace, brass dashed rules between sections.

### 3.2 Enter the Guild — Sign in / Enlist
Design a centered **auth card** on a parchment ground, like a guild admission page. A wax-seal
emblem at the top, title "Welcome back, artisan" (sign-in) or "Enlist with the Guild" (sign-up).
Ledger-style underlined fields: **Username** (helper "3–50 chars · a–z 0–9 _ -") and **Passphrase**
(min 6). A filled ink button "Enter the Hall" / "Enlist". A small-caps switch link between sign-in
and sign-up. A brass note: "Seal of the day — try artisan *sayma* / *password123*." Include the
theme toggle. Show validation as a small red wax "Rejected" mark by the field.

### 3.3 Explore (the main board) — *this is the reference screenshot, reskinned to ContestDB*
Design the browse page exactly in the spirit of the reference. Top nav. Below it a **segmented tab**:
"OPEN COMMISSIONS" (filled ink, red count badge "3") vs "ARCHIVED LEDGERS" (outline), with a
"SORT BY: Chronological ▾" control on the right, and a brass rule beneath.
Then a grid of commission cards using ContestDB's real contests:
- **Featured (large):** engraving of a clockwork observatory; "● LIVE: 1H REMAINING" + black
  "FEATURED" tag; title **"Max Speed Run"**; eyebrow "ROBOTICS · JUDGED BY MAX"; description with a
  drop-cap ("Max speed run of a line-follower robot; deduct 5 points per restart from 100."); dashed
  rule; **BOUNTY / 500 Cr**; avatar stack "+3 enlisted".
- **Side card (stacked-paper look, rounded):** "TRIAL #02" with an expand glyph; title **"Algorithmic
  Trivia"**; description; a **"SEALED" wax tag** + "4 Entries".
- **Dark guild-green card:** eyebrow "WRITING COMMISSION"; muted title **"The Silent Archive"**; a
  **capacity/seal meter** "unlimited enlistment"; geometric engraving mark; "Starts in 3 Days".
- **Two manila cards:** **"Accumulator Math Quiz"** (category chip "QUIZ · JUDGED BY SUM", icon,
  "Prize: 90 Cr", "Voting closes today") and **"Illuminated Capitals"** (chip "CALLIGRAPHY",
  "Prize: 100 Cr", "Starts soon").
Then a full-width **gold dashed divider** with centered "END OF CURRENTLY DISPLAYED LEDGERS", an
outline button **"RETRIEVE MORE ARCHIVES ⤿"**, and the guild footer. Include the theme toggle.

### 3.4 Commission detail (contest page) — tabbed
Design a commission detail page. **Header/hero** on a bordered parchment sheet: status pill (Open /
Sealed / Closed), a category eyebrow ("ROBOTICS · JUDGED BY MAX"), big serif title **"Max Speed
Run"**, a description, and on the right a **countdown** ("ENDS IN 00:35:11", typewriter figures) plus
a primary action button that changes by role: *Guildmaster* → "Enter the Guild Hall"; enlisted
*Artisan* → "Submit an Entry"; guest/not enlisted → "Enlist" / "Enlist with a passphrase". Under the
hero, a **three-stop ledger timeline**: **Commence → The Seal → Conclude**, with a wax-seal marker
on "The Seal" and the current point lit.
Below, a **tab bar**: Overview · Trials · Standing · Statistics · Proclamations · (Guild Hall — only
for Guildmaster/Warden). Show the **Overview** tab: left column = "Judging & Rules" panel, a "Latest
Proclamation" note, and a **top-three Standing** preview; right column = a **Schedule** ledger (Commence
/ Seal / Conclude timestamps), an **Enlistment** count card ("3 / 5 enlisted"), and (admins only) a
**Passphrase** card with a wax seal. Theme toggle present.

### 3.5 Trials tab (tasks) + Submit an Entry (dialog)
Design the **Trials** list inside a commission: each trial row shows an index numeral, title
("Speed Run Time Trial"), description, and a **payload schema** as small ledger chips
(`run_time_seconds :num`, `restarts :num`, "⏱ 30s cooldown"), max score on the right, and a "Submit
Entry" button for enlisted artisans (Guildmasters see "Add Trial").
Then design the **Submit an Entry dialog**: a parchment sheet titled "Submit an Entry — Max Speed
Run", a Trial selector, and **form fields generated from the schema** (numeric fields for
run_time_seconds / restarts, or a code textarea when a field is source_code). A brass note: "Your
entry is checked against the trial's seal before the jury receives it." Buttons: "Seal & Submit" /
"Withdraw". Also design the **judging state** (a rotating brass seal, three chips Pending → Judging →
Sealed) and the **verdict result** card: a big ink-stamped verdict (e.g. **ACCEPTED**, slightly
rotated), the score in typewriter figures ("88"), and a line "Judged by the jury and entered into
the ledger."

### 3.6 The Standing (leaderboard, sealed-aware)
Design the standings page. If the scoreboard is frozen, show a prominent **wax-seal banner**:
for artisans — "The standings are sealed as of 8:31 PM. Final results are revealed when the
commission concludes."; for Guildmasters — an alternate brass banner "Guildmaster's view — live
standings; artisans see the board sealed." Then a **ledger-lined table**: RANK (gold/silver/bronze
**laurel medallions** for top 3), ARTISAN (avatar + name), SCORE (typewriter figures, right-aligned);
highlight the viewer's own row with a brass edge and a "you" tag. Column header reads "Solved" when
the judging method is ICPC, else "Score". Include the theme toggle. Design an empty state
("No entries have been recorded in this ledger yet").

### 3.7 Statistics tab
Design an analytics tab styled as a printed report: **stat plates** (Enlisted, Active, Entries,
Average score) with typewriter numerals; a **submission-activity chart** drawn as engraved bars on
ledger lines; and a **verdict breakdown** as labeled bars (ACCEPTED / PARTIAL / …) with their
ink-stamp colors. Keep it print-report elegant, brass rules, small-caps captions.

### 3.8 Proclamations tab (announcements)
Design a proclamations feed: each proclamation is a **posted notice** on parchment with a small wax
seal, a serif title, body, and "— by *nondiny*, 2h ago". Guildmasters/Wardens see a "Post a
Proclamation" button and a delete (strike) control. Include a compose dialog (Title + Message,
"Publish").

### 3.9 The Guild Hall (host/admin console) — Guildmaster/Warden only
Design the management console. A brass "Guild Hall" banner. **Members & roles** ledger table:
avatar, name, user #, a **role seal** (Guildmaster / Warden / Artisan), and controls to change role
or **"Strike from the rolls"** (kick). A **kick dialog** warns "This permanently strikes the artisan
from re-enlisting; their entries remain in the ledger" with an optional reason. A **Public Visibility**
panel with six ledger toggles (Public standing, Enlistment count, Member roll, Trials before start,
Statistics, Entry counts). A **Danger** panel: "Dissolve this commission" (delete). Everything styled
as guild paperwork with wax seals and brass rules.

### 3.10 My Entries
Design a personal ledger of the signed-in artisan's entries: a table/list grouped by commission,
each row showing the trial, submitted time, an **ink-stamp verdict**, and a monospace score; filters
for verdict/commission; empty state "You have submitted no entries yet."

### 3.11 Judging Panel
Design a panel (for Wardens/Guildmasters and jurors) listing entries **awaiting the jury**: a queue
of entry cards with the payload preview, commission/trial, artisan, submitted time, and a status
(Pending / Judging). Since ContestDB judges automatically, present this as a **read-only jury ledger**
that shows the queue draining Pending → Judging → Sealed in real time, with a note "The jury is
impartial and automatic." (Optional manual-override controls can be shown as sealed/disabled.)

### 3.12 Artisan Profile
Design a profile page: a **crest header** (large monogram avatar, name, "Enlisted since …",
member #), a row of **stat plates** (Avg score, Best, Commissions, Entries). A **Ledger of Labour** —
a GitHub-style activity heatmap rendered as **inked cells on ledger paper** (brass = busiest).
Below, two columns: **Commission history** (rows with laurel rank + score, click to open) and a
**Verdict breakdown** (labeled ink-stamp bars). Theme toggle present.

---

## 4. Reusable component prompts

- **Wax-seal freeze banner:** a horizontal notice with a red/brass wax-seal icon, bold lead line and
  a muted explanation; two variants (artisan "sealed" vs Guildmaster "live view").
- **Verdict stamp:** a slightly-rotated, letterpressed rectangular stamp with distressed edge; color by
  verdict (ACCEPTED ink-green, WRONG_ANSWER burgundy, TLE ochre, PENDING slate); label in mono caps.
- **Rank medallion:** small laurel-wreath medallion for ranks 1–3 (gold/silver/bronze), plain
  typewriter numeral otherwise.
- **Commission card set:** the three variants from §2 (Featured / Standard-manila / Dark-green).
- **Ledger timeline:** three labeled stops (Commence / The Seal / Conclude) with a wax marker at the seal.
- **Schema chip:** small monospace chip for a payload key; a distinct tint for numeric keys and for cooldown.
- **Countdown:** typewriter HH/MM/SS blocks with small-caps unit labels on a manila plate.
- **Theme toggle:** sun ☼ / moon ☾ (or lit lantern) switch, brass framed.
- **Avatar stack:** overlapping monogram avatars with a "+N enlisted" pill.
- **Dashed section divider** with centered small-caps label.

---

## 5. Microcopy & lexicon (keep the world consistent)

- Buttons: **Enlist**, **Enter the Hall**, **Submit an Entry**, **Seal & Submit**, **Retrieve More
  Archives**, **Post a Proclamation**, **Strike from the rolls**, **Dissolve this commission**.
- Statuses: **Open**, **Sealed**, **Closed**, **Unsealed** (pending approval), **Awaiting the jury**.
- Empty/again: "The ledger is empty.", "END OF CURRENTLY DISPLAYED LEDGERS", "All Rights Engraved."
- Roles: **Guildmaster** (host), **Warden** (moderator), **Artisan** (participant).
- Currency: **Cr** (e.g. "500 Cr"). Prizes: "Bounty", "Prize: 100 Cr".
- Footer columns: *Project Info* (Manifesto, Terms of Service, Privacy Parchment) · *Connect*
  (Contact the Scribe, Community Hall, Newsletter). Tagline: "Celebrating the hand-finished quality
  of elite creators since the first ink was pressed."
- Tone: dignified, printed-register, a little ceremonial — never jokey-medieval ("thou", "ye").

---

## 6. Exact tokens (give Stitch these values)

### Parchment (light)
| Token | Hex |
|---|---|
| Ground | `#FBF4E3` |
| Card / manila | `#F5E8C4` |
| Raised / featured sheet | `#FDF8EC` |
| Ink (text) | `#1B1712` |
| Muted ink | `#726651` |
| Burgundy accent | `#9A2A1C` |
| Brass / gold rule | `#B8925A` |
| Guild-green (dark card) | `#14201B` |
| Footer band | `#F3E2B4` |
| Border hairline | `#E1D2A6` |

### Midnight Ledger (dark)
| Token | Hex |
|---|---|
| Ground | `#15120C` |
| Card / leather | `#211B12` |
| Raised | `#2A2317` |
| Ink (text) | `#F0E7D2` |
| Muted ink | `#A99C82` |
| Burgundy accent | `#CD5240` |
| Brass / gold | `#CBA25E` |
| Guild-green surface | `#14201B` |
| Footer band | `#1B1710` |
| Border hairline | `#3A3122` |

### Verdict semantics (both themes; tune lightness per theme)
| Verdict | Light | Dark |
|---|---|---|
| Accepted / Run success | `#2E7D52` | `#4FBE86` |
| Wrong / Failed | `#9A2A1C` | `#E0705E` |
| Timed-out / Partial | `#B07A22` | `#E0A94A` |
| Pending / Judging | `#3F6591` | `#7BA4D8` |
| Rank gold / silver / bronze | `#C9A25E` / `#9AA0A6` / `#B07142` | same, brightened |

### Type
- Display: **Playfair Display** (700/800), tight tracking, letterpress emboss on hero.
- Body: **Lora** or **Source Serif 4** (400/500), ~65-char measure.
- Labels: small-caps, letter-spacing 0.12em (Playfair or IBM Plex Serif).
- Data/mono: **JetBrains Mono** or **Courier Prime**, tabular figures, for scores/ranks/Cr/verdicts/timers/schema keys.

---

### Reminder for Stitch
Deliver **both a light (Parchment) and dark (Midnight Ledger) variant** of every screen, always
include the **theme toggle** in the nav, keep the **serif + typewriter-mono** pairing, and lean into
the **specific** artisan-ledger execution (wax seals, engravings, brass dashed rules, laurel ranks,
illuminated drop-caps, ink-stamp verdicts) so it reads as a deliberate printed register — not a
generic cream-and-serif template.
