# Sensory zużycia (helpery SQL)

Kafelki pod wykresem zużycia korzystają z trzech helperów **SQL** (Ustawienia → Urządzenia i usługi → Dodaj integrację → SQL).
Liczą z długoterminowych statystyk licznika energii pompy, więc pokazują pełny miesiąc także wstecz.
Zamień `sensor.tze284_dikb3dp6_ts0601_energia` na swój licznik energii (kWh, `total_increasing`).

Wspólny fragment:

```sql
-- SID
(SELECT id FROM statistics_meta WHERE statistic_id = 'sensor.tze284_dikb3dp6_ts0601_energia')
```

**Pompa ciepła – zużycie w miesiącu** (kolumna `v`, jednostka `kWh`, klasa `energy`)

```sql
SELECT ROUND(l.sum - p.sum, 2) AS v
FROM (SELECT sum FROM statistics WHERE metadata_id = SID ORDER BY start_ts DESC LIMIT 1) l,
     (SELECT sum FROM statistics WHERE metadata_id = SID
        AND start_ts < CAST(strftime('%s', date('now','localtime','start of month'), 'utc') AS REAL)
        ORDER BY start_ts DESC LIMIT 1) p
```

**Pompa ciepła – zużycie wczoraj** (kolumna `v`, `kWh`, `energy`)

```sql
SELECT ROUND(a.sum - b.sum, 2) AS v
FROM (SELECT sum FROM statistics WHERE metadata_id = SID
        AND start_ts < CAST(strftime('%s', date('now','localtime'), 'utc') AS REAL)
        ORDER BY start_ts DESC LIMIT 1) a,
     (SELECT sum FROM statistics WHERE metadata_id = SID
        AND start_ts < CAST(strftime('%s', date('now','localtime','-1 day'), 'utc') AS REAL)
        ORDER BY start_ts DESC LIMIT 1) b
```

**Pompa ciepła – średnio dziennie w miesiącu** (kolumna `srednia`, `kWh/dzień`, state_class `measurement`)

```sql
SELECT ROUND((l.sum - p.sum) / ((l.start_ts + 3600 - b.t0) / 86400.0), 2) AS srednia
FROM (SELECT CAST(strftime('%s', date('now','localtime','start of month'), 'utc') AS REAL) AS t0) b,
     (SELECT sum, start_ts FROM statistics WHERE metadata_id = SID ORDER BY start_ts DESC LIMIT 1) l,
     (SELECT sum FROM statistics WHERE metadata_id = SID
        AND start_ts < CAST(strftime('%s', date('now','localtime','start of month'), 'utc') AS REAL)
        ORDER BY start_ts DESC LIMIT 1) p
```

W każdym zapytaniu wstaw w miejsce `SID` wspólny fragment (w nawiasach). Działa z domyślną bazą SQLite.
