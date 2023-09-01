import json
import os
import urllib.error
from urllib.request import Request, urlopen


def request(method, url, data=None):
    if not data:
        data = {}
    return json.loads(urlopen(Request(url, method=method, data=json.dumps(data).encode(),
                                      headers={'Accept': 'application/json',
                                               'Authorization': 'Bearer ' + os.getenv('CROWDIN_API'),
                                               'Content-Type': 'application/json'})).read().decode())


for language in request('GET', 'https://crowdin.com/api/v2/languages?limit=500')['data']:
    try:
        progress = request('GET',
                           f'https://crowdin.com/api/v2/projects/610545/languages/{language["data"]["id"]}/progress')
    except urllib.error.HTTPError:
        continue
    if progress['data'][0]['data']['words']['translated']:
        translation = request("POST", "https://crowdin.com/api/v2/projects/610545/translations/exports",
                              {"targetLanguageId": language["data"]["id"], "format": "arb-export",
                               "skipUntranslatedStrings": True, "fileIds": [9]})
        export = urlopen(Request(translation['data']['url'], method='GET')).read()
        open(f"app_{language['data']['osxLocale']}.arb", "wb+").write(export)
