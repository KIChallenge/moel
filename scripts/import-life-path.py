#!/usr/bin/env python3
"""Convert the supplied synthetic example verbatim into a validated bundled fixture."""
from pathlib import Path
from collections import Counter
from datetime import datetime
import argparse
import json
import re

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
args = parser.parse_args()
text = args.source.read_text(encoding='utf-8')
root = Path(__file__).resolve().parents[1]
output = root / 'apps/ios/Sovi/Resources/Fixtures'
headers = list(re.finditer(r'^(\d{4}) \| (.+?) \| (.+)$', text, re.M))
day_headers = list(re.finditer(r'^(P\d{3}) \| (\d{2}\.\d{2}\.\d{4}) \| BUTTON: (.+)$', text, re.M))
entries_pattern = re.compile(r'^  (\d+)\. (.+?) \[([^|\]]+) \| ([^\]]+)\]\n((?:     .*\n?)+)', re.M)
days = []
for index, header in enumerate(day_headers):
    end = day_headers[index + 1].start() if index + 1 < len(day_headers) else text.index('VERHALTEN DER SUB-BUTTONS', header.end())
    block = text[header.start():end]
    year_header = next(h for h in reversed(headers) if h.start() < header.start())
    age = re.search(r'^  Alter: (.+?) \| Halo: ', block, re.M).group(1)
    relation = re.search(r'^  Zusammenhang: (.+)$', block, re.M)
    expected_count = int(re.search(r'\((\d+) Eintr(?:ag|äge)\)', block).group(1))
    entries = []
    for match in entries_pattern.finditer(block):
        body = match.group(5).rstrip()
        origin = re.search(r'^     Herkunft: (.+)$', body, re.M)
        detail = body[:origin.start()] if origin else body
        entries.append({
            'number': int(match.group(1)), 'title': match.group(2),
            'category': match.group(3).strip(), 'status': match.group(4).strip(),
            'detail': ' '.join(line.strip() for line in detail.splitlines()).strip(),
            'origin': origin.group(1) if origin else 'Im Beispieldatensatz nicht angegeben.',
            'passage': match.group(0).rstrip(),
        })
    assert len(entries) == expected_count, (header.group(1), expected_count, len(entries))
    assert [e['number'] for e in entries] == list(range(1, expected_count + 1))
    date = datetime.strptime(header.group(2), '%d.%m.%Y')
    days.append({
        'id': header.group(1), 'date': header.group(2), 'title': header.group(3),
        'year': date.year, 'stage': year_header.group(2), 'age': age,
        'episodeIDs': relation.group(1).split(', ') if relation else [],
        'planned': date.date() > datetime(2026, 11, 5).date(), 'entries': entries,
    })

references = []
for match in re.finditer(r'^\[(Q\d)\] ([\s\S]*?)(?=^\[Q\d\]|^ENDE DER TXT-DATEI)', text, re.M):
    body = match.group(2).strip()
    references.append({'id': match.group(1), 'text': body, 'urls': re.findall(r'https://[^\s]+', body)})

assert len(days) == 222
assert sum(len(day['entries']) for day in days) == 328
assert sum(len(day['entries']) > 1 for day in days) == 73
assert sum(day['planned'] for day in days) == 5
assert len({day['date'] for day in days}) == 222
assert [day['date'] for day in days] == [day['date'] for day in sorted(days, key=lambda d: datetime.strptime(d['date'], '%d.%m.%Y'))]
assert len(references) == 10
fixture = {'version': 1, 'birthDate': '12.03.1993', 'snapshot': '2026-11-05T09:00:00+01:00',
           'timeZone': 'Europe/Vienna', 'age': 33, 'sex': 'männlich', 'days': days, 'references': references}
output.mkdir(parents=True, exist_ok=True)
(output / 'life-path-33.json').write_text(json.dumps(fixture, ensure_ascii=False, indent=2) + '\n')
(output / 'life-path-33.txt').write_text(text)
print('Validated 222 unique days, 328 entries, 73 segmented halos, 217 current/historical days and 5 planned days.')
print('Categories:', dict(Counter(e['category'] for d in days for e in d['entries'])))
