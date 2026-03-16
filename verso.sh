#!/bin/sh
# ═══════════════════════════════════════════════════
#  V E R S O  —  Reading Stats for Kobo
# ═══════════════════════════════════════════════════
#  Queries the Kobo SQLite database and generates
#  an HTML dashboard for the built-in browser.
# ═══════════════════════════════════════════════════

# ── Ensure PATH covers common Kobo binary locations ──
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

# ── Configuration ─────────────────────────────────
DB="/mnt/onboard/.kobo/KoboReader.sqlite"
OUT_DIR="/mnt/onboard/.adds/verso"
HTML="$OUT_DIR/dashboard.html"
TMP="$OUT_DIR/.verso.tmp.html"
TMPDATA="/tmp/verso_data"

# ── Error page helper ────────────────────────────
error_page() {
    cat > "$HTML" << ERREOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Verso Error</title>
<style>body{font-family:Georgia,serif;padding:40px;text-align:center}h1{font-size:2em}p{font-size:1.1em;margin:16px 0}.mono{font-family:'Courier New',monospace;background:#eee;padding:8px 12px;display:inline-block;margin:8px 0}</style>
</head><body><h1>Verso</h1><p>$1</p><p class="mono">$2</p></body></html>
ERREOF
    exit 0
}

# ── Preflight ─────────────────────────────────────
mkdir -p "$OUT_DIR"

if [ ! -f "$DB" ]; then
    error_page "Database not found." "$DB"
fi

# Find sqlite3 — prefer bundled binary, then check system paths
SQL=""
BUNDLED="$OUT_DIR/sqlite3"

if [ -f "$BUNDLED" ]; then
    chmod +x "$BUNDLED" 2>/dev/null
    SQL="$BUNDLED"
fi

if [ -z "$SQL" ]; then
    for p in sqlite3 /usr/bin/sqlite3 /bin/sqlite3 /usr/local/bin/sqlite3; do
        if [ -x "$p" ] 2>/dev/null || command -v "$p" >/dev/null 2>&1; then
            SQL="$p"
            break
        fi
    done
fi

if [ -z "$SQL" ]; then
    error_page "sqlite3 not found." "Place the sqlite3 binary in $OUT_DIR/"
fi

NOW=$(date '+%B %d, %Y' 2>/dev/null || echo "Unknown date")

# ── SQL Helpers ───────────────────────────────────
# HTML-escaped column expressions
ET="replace(replace(replace(COALESCE(Title,'Untitled'),'&','&amp;'),'<','&lt;'),'>','&gt;')"
EA="replace(replace(replace(COALESCE(Attribution,'Unknown'),'&','&amp;'),'<','&lt;'),'>','&gt;')"

# Percent read — handles both 0–1 and 0–100 storage
PCT="CASE WHEN COALESCE(___PercentRead,0)<=1 THEN CAST(COALESCE(___PercentRead,0)*100 AS INTEGER) ELSE CAST(COALESCE(___PercentRead,0) AS INTEGER) END"

# Format seconds to readable time
TFMT="CASE WHEN COALESCE(TimeSpentReading,0)>=86400 THEN CAST(TimeSpentReading/86400 AS INTEGER)||'d '||CAST((TimeSpentReading%86400)/3600 AS INTEGER)||'h' WHEN COALESCE(TimeSpentReading,0)>=3600 THEN CAST(TimeSpentReading/3600 AS INTEGER)||'h '||CAST((TimeSpentReading%3600)/60 AS INTEGER)||'m' ELSE CAST(COALESCE(TimeSpentReading,0)/60 AS INTEGER)||'m' END"

# ── Gather Overview Stats ─────────────────────────
TOTAL=$($SQL "$DB" "SELECT COUNT(*) FROM content WHERE ContentType=6;")
BOOKS_READ=$($SQL "$DB" "SELECT COUNT(*) FROM content WHERE ContentType=6 AND ReadStatus=2;")
BOOKS_READING=$($SQL "$DB" "SELECT COUNT(*) FROM content WHERE ContentType=6 AND ReadStatus=1;")
BOOKS_UNREAD=$($SQL "$DB" "SELECT COUNT(*) FROM content WHERE ContentType=6 AND ReadStatus=0;")

TOTAL_SEC=$($SQL "$DB" "SELECT COALESCE(SUM(TimeSpentReading),0) FROM content WHERE ContentType=6;")
TOTAL_SEC=${TOTAL_SEC:-0}

TOTAL_D=$((TOTAL_SEC / 86400))
TOTAL_H=$(( (TOTAL_SEC % 86400) / 3600 ))
TOTAL_M=$(( (TOTAL_SEC % 3600) / 60 ))

if [ "$TOTAL_D" -gt 0 ] 2>/dev/null; then
    TOTAL_TIME="${TOTAL_D}d ${TOTAL_H}h ${TOTAL_M}m"
elif [ "$TOTAL_H" -gt 0 ] 2>/dev/null; then
    TOTAL_TIME="${TOTAL_H}h ${TOTAL_M}m"
else
    TOTAL_TIME="${TOTAL_M}m"
fi

AVG_SEC=$($SQL "$DB" "SELECT CAST(COALESCE(AVG(TimeSpentReading),0) AS INTEGER) FROM content WHERE ContentType=6 AND ReadStatus=2 AND TimeSpentReading>0;")
AVG_SEC=${AVG_SEC:-0}
AVG_H=$((AVG_SEC / 3600))
AVG_M=$(( (AVG_SEC % 3600) / 60 ))
if [ "$AVG_H" -gt 0 ] 2>/dev/null; then
    AVG_TIME="${AVG_H}h ${AVG_M}m"
else
    AVG_TIME="${AVG_M}m"
fi

HIGHLIGHTS=$($SQL "$DB" "SELECT COUNT(*) FROM Bookmark;" 2>/dev/null || echo "0")
ANNOTATIONS=$($SQL "$DB" "SELECT COUNT(*) FROM Bookmark WHERE Annotation IS NOT NULL AND Annotation != '';" 2>/dev/null || echo "0")

# Library composition percentages
if [ "$TOTAL" -gt 0 ] 2>/dev/null && [ "$TOTAL" -ne 0 ]; then
    READ_PCT=$((BOOKS_READ * 100 / TOTAL))
    READING_PCT=$((BOOKS_READING * 100 / TOTAL))
    UNREAD_PCT=$((100 - READ_PCT - READING_PCT))
else
    READ_PCT=0
    READING_PCT=0
    UNREAD_PCT=100
fi

# Longest book
LONGEST_TITLE=$($SQL "$DB" "SELECT $ET FROM content WHERE ContentType=6 AND TimeSpentReading>0 ORDER BY TimeSpentReading DESC LIMIT 1;")
LONGEST_TIME=$($SQL "$DB" "SELECT $TFMT FROM content WHERE ContentType=6 AND TimeSpentReading>0 ORDER BY TimeSpentReading DESC LIMIT 1;")

# Shortest finished book
SHORTEST_TITLE=$($SQL "$DB" "SELECT $ET FROM content WHERE ContentType=6 AND ReadStatus=2 AND TimeSpentReading>0 ORDER BY TimeSpentReading ASC LIMIT 1;")
SHORTEST_TIME=$($SQL "$DB" "SELECT $TFMT FROM content WHERE ContentType=6 AND ReadStatus=2 AND TimeSpentReading>0 ORDER BY TimeSpentReading ASC LIMIT 1;")

# Total authors
TOTAL_AUTHORS=$($SQL "$DB" "SELECT COUNT(DISTINCT Attribution) FROM content WHERE ContentType=6 AND Attribution IS NOT NULL AND Attribution != '';")

# ══════════════════════════════════════════════════
#  BUILD HTML
# ══════════════════════════════════════════════════

cat > "$TMP" << 'CSSEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Verso</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{
    font-family:Georgia,'Times New Roman',serif;
    background:#fff;color:#000;
    padding:28px 24px 40px;
    max-width:1200px;margin:0 auto;
    line-height:1.5;
    -webkit-text-size-adjust:100%;
}

/* ── Header ── */
.header{text-align:center;padding:10px 0 28px;border-bottom:3px double #000;margin-bottom:32px}
.logo{font-size:2.8em;font-weight:normal;letter-spacing:0.55em;text-transform:uppercase;margin-right:-0.55em}
.tagline{font-style:italic;font-size:0.9em;margin-top:2px}
.updated{font-size:0.7em;margin-top:14px;letter-spacing:0.08em;text-transform:uppercase}

/* ── Section Titles ── */
.section-title{
    display:-webkit-flex;display:flex;
    -webkit-align-items:center;align-items:center;
    gap:16px;margin:40px 0 18px;
    font-size:0.8em;font-weight:normal;
    letter-spacing:0.2em;text-transform:uppercase;
}
.section-title::before,.section-title::after{
    content:'';-webkit-flex:1;flex:1;height:1px;background:#000
}

/* ── Stat Cards ── */
.cards{display:-webkit-flex;display:flex;-webkit-flex-wrap:wrap;flex-wrap:wrap;gap:10px;justify-content:center}
.card{border:2px solid #000;padding:14px 10px;text-align:center;min-width:120px;-webkit-flex:1;flex:1}
.card-number{font-family:'Courier New',Courier,monospace;font-size:2.6em;font-weight:bold;line-height:1.1}
.card-label{font-size:0.65em;text-transform:uppercase;letter-spacing:0.15em;margin-top:4px}

/* ── Time Display ── */
.time-row{display:-webkit-flex;display:flex;gap:10px;margin:14px 0}
.time-box{border:2px solid #000;padding:18px 14px;text-align:center;-webkit-flex:1;flex:1}
.time-big{font-family:'Courier New',Courier,monospace;font-size:2em;font-weight:bold}
.time-label{font-size:0.72em;text-transform:uppercase;letter-spacing:0.1em;margin-top:2px}

/* ── Records ── */
.records{display:-webkit-flex;display:flex;gap:10px;margin:10px 0}
.record{border:1px solid #000;padding:12px 14px;-webkit-flex:1;flex:1}
.record-label{font-size:0.7em;text-transform:uppercase;letter-spacing:0.08em;margin-bottom:4px}
.record-title{font-weight:bold;font-size:0.95em}
.record-value{font-family:'Courier New',Courier,monospace;font-size:0.85em;margin-top:2px}

/* ── Bar Charts ── */
.bar-chart{margin:8px 0}
.bar-row{display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center;margin:4px 0}
.bar-label{width:90px;font-size:0.75em;text-align:right;padding-right:10px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-family:'Courier New',Courier,monospace}
.bar-label-wide{width:220px;font-family:Georgia,serif;font-size:0.8em}
.bar-track{-webkit-flex:1;flex:1;height:16px;border:1px solid #000;background:#fff}
.bar-fill{height:100%;background:#000;min-width:1px}
.bar-value{width:55px;font-size:0.75em;padding-left:8px;font-family:'Courier New',Courier,monospace;text-align:right}

/* ── Tables ── */
table{width:100%;border-collapse:collapse;margin:8px 0}
th{text-align:left;border-bottom:2px solid #000;padding:8px 6px;font-size:0.7em;text-transform:uppercase;letter-spacing:0.08em;font-weight:normal}
td{border-bottom:1px solid #000;padding:9px 6px;font-size:0.85em;vertical-align:top}
td small{font-style:italic;font-size:0.9em}
td .mono{font-family:'Courier New',Courier,monospace;font-size:0.9em}
tr:last-child td{border-bottom:none}

/* ── Book Cards ── */
.book-card{border:1px solid #000;padding:12px 16px;margin:8px 0}
.book-title{font-size:1em;font-weight:bold}
.book-author{font-style:italic;font-size:0.82em;margin-bottom:8px}
.book-meta{display:-webkit-flex;display:flex;-webkit-justify-content:space-between;justify-content:space-between;font-family:'Courier New',Courier,monospace;font-size:0.78em;margin-top:6px}

/* ── Progress Bars ── */
.progress-track{width:100%;height:11px;border:1px solid #000;background:#fff}
.progress-fill{height:100%;background:#000}

/* ── Composition Bar ── */
.comp-bar{display:-webkit-flex;display:flex;height:26px;border:2px solid #000;overflow:hidden;margin:14px 0}
.comp-read{background:#000;height:100%}
.comp-reading{background:repeating-linear-gradient(45deg,#000,#000 2px,#fff 2px,#fff 4px);height:100%}
.comp-unread{background:#fff;height:100%}
.comp-legend{display:-webkit-flex;display:flex;-webkit-justify-content:center;justify-content:center;gap:20px;font-size:0.78em;margin-top:8px}
.comp-legend-item{display:-webkit-flex;display:flex;-webkit-align-items:center;align-items:center;gap:6px}
.comp-swatch{width:13px;height:13px;border:1px solid #000}

/* ── Annotation Stats ── */
.anno-cards{display:-webkit-flex;display:flex;gap:10px;margin:10px 0}
.anno-card{border:1px solid #000;padding:14px;text-align:center;-webkit-flex:1;flex:1}
.anno-number{font-family:'Courier New',Courier,monospace;font-size:2em;font-weight:bold;line-height:1.1}
.anno-label{font-size:0.7em;text-transform:uppercase;letter-spacing:0.1em;margin-top:2px}

/* ── Exit Button ── */
.exit-btn{
    display:block;width:100%;padding:14px 0;margin:18px 0;
    font-family:Georgia,'Times New Roman',serif;font-size:0.85em;
    letter-spacing:0.2em;text-transform:uppercase;
    background:#000;color:#fff;border:2px solid #000;
    cursor:pointer;text-align:center;
    -webkit-appearance:none;appearance:none;
}
.exit-btn:active{background:#fff;color:#000}

/* ── Footer ── */
.footer{text-align:center;margin-top:44px;padding-top:14px;border-top:1px solid #000;font-size:0.7em;letter-spacing:0.12em;text-transform:uppercase}
.footer-sub{font-size:0.85em;font-style:italic;text-transform:none;letter-spacing:0;margin-top:4px}

/* ── Empty State ── */
.empty{font-style:italic;text-align:center;padding:16px;font-size:0.9em}
</style>
</head>
<body>
CSSEOF

# ── HEADER ────────────────────────────────────────
cat >> "$TMP" << EOF
<div class="header">
<div class="logo">Verso</div>
<div class="tagline">Your Reading Chronicle</div>
<div class="updated">$NOW</div>
</div>
<button class="exit-btn" onclick="window.close();history.back();location.href='about:blank'">Close</button>
EOF

# ── OVERVIEW CARDS ────────────────────────────────
cat >> "$TMP" << EOF
<div class="cards">
<div class="card"><div class="card-number">$TOTAL</div><div class="card-label">Books</div></div>
<div class="card"><div class="card-number">$BOOKS_READ</div><div class="card-label">Finished</div></div>
<div class="card"><div class="card-number">$BOOKS_READING</div><div class="card-label">Reading</div></div>
<div class="card"><div class="card-number">$BOOKS_UNREAD</div><div class="card-label">Unread</div></div>
</div>
EOF

# ── READING TIME ──────────────────────────────────
cat >> "$TMP" << EOF
<div class="section-title">Time Spent Reading</div>
<div class="time-row">
<div class="time-box"><div class="time-big">$TOTAL_TIME</div><div class="time-label">Total</div></div>
<div class="time-box"><div class="time-big">$AVG_TIME</div><div class="time-label">Avg per Book</div></div>
<div class="time-box"><div class="time-big">$TOTAL_AUTHORS</div><div class="time-label">Authors</div></div>
</div>
EOF

# ── RECORDS ───────────────────────────────────────
if [ -n "$LONGEST_TITLE" ]; then
cat >> "$TMP" << EOF
<div class="records">
<div class="record">
<div class="record-label">Most Time Spent</div>
<div class="record-title">$LONGEST_TITLE</div>
<div class="record-value">$LONGEST_TIME</div>
</div>
<div class="record">
<div class="record-label">Fastest Finish</div>
<div class="record-title">$SHORTEST_TITLE</div>
<div class="record-value">$SHORTEST_TIME</div>
</div>
</div>
EOF
fi

# ── CURRENTLY READING ─────────────────────────────
READING_COUNT=$($SQL "$DB" "SELECT COUNT(*) FROM content WHERE ContentType=6 AND ReadStatus=1;")

cat >> "$TMP" << 'SECEOF'
<div class="section-title">Currently Reading</div>
SECEOF

if [ "$READING_COUNT" -gt 0 ] 2>/dev/null && [ "$READING_COUNT" -ne 0 ]; then
    $SQL "$DB" "SELECT $ET, $EA, $PCT, $TFMT, COALESCE(DateLastRead,'') FROM content WHERE ContentType=6 AND ReadStatus=1 ORDER BY DateLastRead DESC LIMIT 15;" | while IFS='|' read -r title author pct tspent lastread; do
        pct=${pct:-0}
        cat >> "$TMP" << EOF
<div class="book-card">
<div class="book-title">$title</div>
<div class="book-author">$author</div>
<div class="progress-track"><div class="progress-fill" style="width:${pct}%"></div></div>
<div class="book-meta"><span>${pct}% complete</span><span>$tspent</span></div>
</div>
EOF
    done
else
    echo '<p class="empty">No books in progress.</p>' >> "$TMP"
fi

# ── BOOKS COMPLETED PER MONTH (Bar Chart) ────────
cat >> "$TMP" << 'SECEOF'
<div class="section-title">Monthly Completions</div>
SECEOF

$SQL "$DB" "SELECT strftime('%Y-%m', DateLastRead), COUNT(*) FROM content WHERE ContentType=6 AND ReadStatus=2 AND DateLastRead IS NOT NULL GROUP BY strftime('%Y-%m', DateLastRead) ORDER BY strftime('%Y-%m', DateLastRead) DESC LIMIT 12;" > "${TMPDATA}_monthly" 2>/dev/null

MAX_M=$(awk -F'|' 'BEGIN{m=0}{if($2+0>m)m=$2+0}END{print m}' "${TMPDATA}_monthly" 2>/dev/null)
MAX_M=${MAX_M:-0}

if [ "$MAX_M" -gt 0 ] 2>/dev/null && [ "$MAX_M" -ne 0 ]; then
    echo '<div class="bar-chart">' >> "$TMP"
    awk -F'|' -v max="$MAX_M" '{
        pct = int($2 * 100 / max);
        if (pct < 1 && $2 > 0) pct = 1;
        printf "<div class=\"bar-row\"><span class=\"bar-label\">%s</span><div class=\"bar-track\"><div class=\"bar-fill\" style=\"width:%d%%\"></div></div><span class=\"bar-value\">%s</span></div>\n", $1, pct, $2
    }' "${TMPDATA}_monthly" >> "$TMP"
    echo '</div>' >> "$TMP"
else
    echo '<p class="empty">No completed books yet.</p>' >> "$TMP"
fi

rm -f "${TMPDATA}_monthly"

# ── TOP BOOKS BY READING TIME (Bar Chart) ────────
cat >> "$TMP" << 'SECEOF'
<div class="section-title">Most Time Invested</div>
SECEOF

$SQL "$DB" "SELECT $ET, COALESCE(TimeSpentReading,0), $TFMT FROM content WHERE ContentType=6 AND TimeSpentReading>0 ORDER BY TimeSpentReading DESC LIMIT 10;" > "${TMPDATA}_topbooks" 2>/dev/null

MAX_T=$(awk -F'|' 'BEGIN{m=0}{if($2+0>m)m=$2+0}END{print m}' "${TMPDATA}_topbooks" 2>/dev/null)
MAX_T=${MAX_T:-0}

if [ "$MAX_T" -gt 0 ] 2>/dev/null && [ "$MAX_T" -ne 0 ]; then
    echo '<div class="bar-chart">' >> "$TMP"
    awk -F'|' -v max="$MAX_T" '{
        pct = int($2 * 100 / max);
        if (pct < 1 && $2 > 0) pct = 1;
        title = $1;
        if (length(title) > 35) title = substr(title, 1, 32) "...";
        printf "<div class=\"bar-row\"><span class=\"bar-label bar-label-wide\">%s</span><div class=\"bar-track\"><div class=\"bar-fill\" style=\"width:%d%%\"></div></div><span class=\"bar-value\">%s</span></div>\n", title, pct, $3
    }' "${TMPDATA}_topbooks" >> "$TMP"
    echo '</div>' >> "$TMP"
else
    echo '<p class="empty">No reading data yet.</p>' >> "$TMP"
fi

rm -f "${TMPDATA}_topbooks"

# ── TOP AUTHORS ───────────────────────────────────
cat >> "$TMP" << 'SECEOF'
<div class="section-title">Top Authors</div>
SECEOF

$SQL "$DB" "SELECT $EA, COUNT(*), COALESCE(SUM(TimeSpentReading),0), SUM(CASE WHEN ReadStatus=2 THEN 1 ELSE 0 END) FROM content WHERE ContentType=6 AND Attribution IS NOT NULL AND Attribution != '' GROUP BY Attribution ORDER BY SUM(TimeSpentReading) DESC LIMIT 10;" > "${TMPDATA}_authors" 2>/dev/null

if [ -s "${TMPDATA}_authors" ]; then
    cat >> "$TMP" << 'TBLEOF'
<table>
<tr><th>Author</th><th>Books</th><th>Finished</th><th>Time</th></tr>
TBLEOF
    awk -F'|' '{
        sec = $3 + 0;
        if (sec >= 3600) {
            h = int(sec / 3600);
            m = int((sec % 3600) / 60);
            t = h "h " m "m";
        } else {
            t = int(sec / 60) "m";
        }
        author = $1;
        if (length(author) > 30) author = substr(author, 1, 27) "...";
        printf "<tr><td>%s</td><td class=\"mono\">%s</td><td class=\"mono\">%s</td><td class=\"mono\">%s</td></tr>\n", author, $2, $4, t
    }' "${TMPDATA}_authors" >> "$TMP"
    echo '</table>' >> "$TMP"
else
    echo '<p class="empty">No author data available.</p>' >> "$TMP"
fi

rm -f "${TMPDATA}_authors"

# ── RECENTLY FINISHED ─────────────────────────────
cat >> "$TMP" << 'SECEOF'
<div class="section-title">Recently Finished</div>
SECEOF

FINISHED_COUNT=$($SQL "$DB" "SELECT COUNT(*) FROM content WHERE ContentType=6 AND ReadStatus=2;")

if [ "$FINISHED_COUNT" -gt 0 ] 2>/dev/null && [ "$FINISHED_COUNT" -ne 0 ]; then
    cat >> "$TMP" << 'TBLEOF'
<table>
<tr><th>Title</th><th>Author</th><th>Time</th><th>Finished</th></tr>
TBLEOF
    $SQL "$DB" "SELECT $ET, $EA, $TFMT, COALESCE(strftime('%Y-%m-%d', DateLastRead),'—') FROM content WHERE ContentType=6 AND ReadStatus=2 AND DateLastRead IS NOT NULL ORDER BY DateLastRead DESC LIMIT 15;" | awk -F'|' '{
        title = $1;
        if (length(title) > 32) title = substr(title, 1, 29) "...";
        printf "<tr><td><strong>%s</strong></td><td><small>%s</small></td><td class=\"mono\">%s</td><td class=\"mono\">%s</td></tr>\n", title, $2, $3, $4
    }' >> "$TMP"
    echo '</table>' >> "$TMP"
else
    echo '<p class="empty">No finished books yet.</p>' >> "$TMP"
fi

# ── HIGHLIGHTS & ANNOTATIONS ─────────────────────
cat >> "$TMP" << EOF
<div class="section-title">Annotations</div>
<div class="anno-cards">
<div class="anno-card"><div class="anno-number">$HIGHLIGHTS</div><div class="anno-label">Highlights</div></div>
<div class="anno-card"><div class="anno-number">$ANNOTATIONS</div><div class="anno-label">Notes</div></div>
</div>
EOF

# Most highlighted books
$SQL "$DB" "SELECT $ET, COUNT(*) FROM Bookmark b JOIN content c ON b.VolumeID = c.ContentID WHERE c.ContentType=6 GROUP BY c.ContentID ORDER BY COUNT(*) DESC LIMIT 5;" > "${TMPDATA}_highlighted" 2>/dev/null

if [ -s "${TMPDATA}_highlighted" ]; then
    cat >> "$TMP" << 'TBLEOF'
<table>
<tr><th>Most Annotated</th><th>Count</th></tr>
TBLEOF
    awk -F'|' '{
        title = $1;
        if (length(title) > 40) title = substr(title, 1, 37) "...";
        printf "<tr><td>%s</td><td class=\"mono\">%s</td></tr>\n", title, $2
    }' "${TMPDATA}_highlighted" >> "$TMP"
    echo '</table>' >> "$TMP"
fi

rm -f "${TMPDATA}_highlighted"

# ── LIBRARY COMPOSITION ──────────────────────────
cat >> "$TMP" << EOF
<div class="section-title">Library</div>
<div class="comp-bar">
<div class="comp-read" style="width:${READ_PCT}%"></div>
<div class="comp-reading" style="width:${READING_PCT}%"></div>
<div class="comp-unread" style="width:${UNREAD_PCT}%"></div>
</div>
<div class="comp-legend">
<div class="comp-legend-item"><div class="comp-swatch" style="background:#000"></div>Finished · ${READ_PCT}%</div>
<div class="comp-legend-item"><div class="comp-swatch" style="background:repeating-linear-gradient(45deg,#000,#000 2px,#fff 2px,#fff 4px)"></div>Reading · ${READING_PCT}%</div>
<div class="comp-legend-item"><div class="comp-swatch" style="background:#fff"></div>Unread · ${UNREAD_PCT}%</div>
</div>
EOF

# ── DAY-OF-WEEK PATTERNS ─────────────────────────
$SQL "$DB" "SELECT
    CASE CAST(strftime('%w', DateLastRead) AS INTEGER)
        WHEN 0 THEN 'Sun'
        WHEN 1 THEN 'Mon'
        WHEN 2 THEN 'Tue'
        WHEN 3 THEN 'Wed'
        WHEN 4 THEN 'Thu'
        WHEN 5 THEN 'Fri'
        WHEN 6 THEN 'Sat'
    END,
    COUNT(*)
FROM content
WHERE ContentType=6 AND ReadStatus=2 AND DateLastRead IS NOT NULL
GROUP BY strftime('%w', DateLastRead)
ORDER BY CAST(strftime('%w', DateLastRead) AS INTEGER);" > "${TMPDATA}_dow" 2>/dev/null

MAX_DOW=$(awk -F'|' 'BEGIN{m=0}{if($2+0>m)m=$2+0}END{print m}' "${TMPDATA}_dow" 2>/dev/null)
MAX_DOW=${MAX_DOW:-0}

if [ "$MAX_DOW" -gt 0 ] 2>/dev/null && [ "$MAX_DOW" -ne 0 ]; then
    cat >> "$TMP" << 'SECEOF'
<div class="section-title">Books Finished by Day</div>
<div class="bar-chart">
SECEOF
    awk -F'|' -v max="$MAX_DOW" '{
        pct = int($2 * 100 / max);
        if (pct < 1 && $2 > 0) pct = 1;
        printf "<div class=\"bar-row\"><span class=\"bar-label\">%s</span><div class=\"bar-track\"><div class=\"bar-fill\" style=\"width:%d%%\"></div></div><span class=\"bar-value\">%s</span></div>\n", $1, pct, $2
    }' "${TMPDATA}_dow" >> "$TMP"
    echo '</div>' >> "$TMP"
fi

rm -f "${TMPDATA}_dow"

# ── YEARLY SUMMARY ────────────────────────────────
$SQL "$DB" "SELECT
    strftime('%Y', DateLastRead),
    COUNT(*),
    COALESCE(SUM(TimeSpentReading),0)
FROM content
WHERE ContentType=6 AND ReadStatus=2 AND DateLastRead IS NOT NULL
GROUP BY strftime('%Y', DateLastRead)
ORDER BY strftime('%Y', DateLastRead) DESC
LIMIT 5;" > "${TMPDATA}_yearly" 2>/dev/null

if [ -s "${TMPDATA}_yearly" ]; then
    cat >> "$TMP" << 'SECEOF'
<div class="section-title">Year in Review</div>
<table>
<tr><th>Year</th><th>Books</th><th>Reading Time</th></tr>
SECEOF
    awk -F'|' '{
        sec = $3 + 0;
        d = int(sec / 86400);
        h = int((sec % 86400) / 3600);
        if (d > 0) t = d "d " h "h";
        else if (h > 0) { m = int((sec % 3600) / 60); t = h "h " m "m"; }
        else { t = int(sec / 60) "m"; }
        printf "<tr><td class=\"mono\">%s</td><td class=\"mono\">%s</td><td class=\"mono\">%s</td></tr>\n", $1, $2, t
    }' "${TMPDATA}_yearly" >> "$TMP"
    echo '</table>' >> "$TMP"
fi

rm -f "${TMPDATA}_yearly"

# ── FOOTER ────────────────────────────────────────
cat >> "$TMP" << 'FOOTEOF'
<button class="exit-btn" onclick="window.close();history.back();location.href='about:blank'">Close</button>
<div class="footer">
Verso
<div class="footer-sub">reading stats for kobo</div>
</div>
</body>
</html>
FOOTEOF

# ── Finalize ──────────────────────────────────────
mv "$TMP" "$HTML"
printf "Verso: %s books analyzed\n" "$TOTAL"
exit 0
