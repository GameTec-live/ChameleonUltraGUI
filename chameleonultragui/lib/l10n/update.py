import json
import os
import re
import sys
import urllib.error
from urllib.request import Request, urlopen


PROJECT_ID = 611911
FILE_ID = 33
API_URL = 'https://crowdin.com/api/v2'
LOCALE_PATTERN = re.compile(r'^[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)*$')


def progressbar(it, prefix='', size=60, out=sys.stdout):
    count = len(it)

    def show(j):
        x = int(size * j / count)
        print(f"{prefix}[{'#' * x}{('.' * (size - x))}] {j}/{count}", end='\r', file=out, flush=True)

    show(0)
    for i, item in enumerate(it):
        yield item
        show(i + 1)
    print('\n', flush=True, file=out)


def request(method, url, data=None):
    body = None if data is None else json.dumps(data).encode()
    return json.loads(urlopen(Request(url, method=method, data=body,
                                      headers={'Accept': 'application/json',
                                               'Authorization': 'Bearer ' + os.getenv('CROWDIN_API'),
                                               'Content-Type': 'application/json'})).read().decode())


def get_language_mappings():
    project = request('GET', f'{API_URL}/projects/{PROJECT_ID}')['data']
    return project.get('languageMapping') or {}


def resolve_locale(language_id, translations, language_mappings):
    mapping = language_mappings.get(language_id) or {}
    candidates = (mapping.get('locale'), translations.get('@@locale'), language_id)

    for candidate in candidates:
        if not isinstance(candidate, str) or not candidate.strip():
            continue

        locale = candidate.strip().replace('-', '_')
        if not LOCALE_PATTERN.fullmatch(locale):
            raise ValueError(f'Invalid locale {candidate!r} for Crowdin language {language_id!r}')
        return locale

    raise ValueError(f'No locale available for Crowdin language {language_id!r}')


def main():
    language_mappings = get_language_mappings()
    languages = request(
        'GET',
        f'{API_URL}/projects/{PROJECT_ID}/files/{FILE_ID}/languages/progress?limit=500',
    )['data']

    for language in progressbar(languages):
        language_id = language['data']['languageId']
        try:
            progress = request(
                'GET',
                f'{API_URL}/projects/{PROJECT_ID}/languages/{language_id}/progress',
            )
        except urllib.error.HTTPError:
            continue

        words = progress['data'][0]['data']['words']
        if words['total'] and words['translated'] / words['total'] >= 0.7:
            try:
                translation = request(
                    'POST',
                    f'{API_URL}/projects/{PROJECT_ID}/translations/exports',
                    {
                        'targetLanguageId': language_id,
                        'format': 'arb-export',
                        'skipUntranslatedStrings': True,
                        'fileIds': [FILE_ID],
                    },
                )
            except urllib.error.HTTPError:
                continue

            export = urlopen(Request(translation['data']['url'], method='GET')).read()
            translations = json.loads(export.decode())
            locale = resolve_locale(language_id, translations, language_mappings)
            translations['@@locale'] = locale
            with open(f'app_{locale}.arb', 'w', encoding='utf-8') as output:
                json.dump(translations, output, indent=2)


if __name__ == '__main__':
    main()
