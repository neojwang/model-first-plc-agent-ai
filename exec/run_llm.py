#!/usr/bin/env python3
"""Generate the LLM responses of a run plan through the OpenAI Responses API.

Every lane is a new conversation. The A1 lane (IDEF0, then GRAFCET JSON, then ST) is one conversation of three
turns; the A2 lane is another conversation that has not seen the A1 artifacts; the baseline is one turn. Prompts
are rendered exactly as render_prompt.py renders them, and the settings of the access route are fixed for the
experiment and written into every record.

Access routes (same model, same prompts, same transcription rule):
  api      an OpenAI API key, read from OPENAI_API_KEY, the macOS keychain item 'openai-api-key', or the file
           openai_api_key in the credential folder; one JSON response per call; max_output_tokens 64000.
  chatgpt  ChatGPT plan usage through Sign in with ChatGPT (OAuth; Plus or Pro; no API key). The route requires
           store=false and stream=true and does not accept max_output_tokens, so responses are streamed and the
           model's own output limit applies. When the plan's usage limit is reached, the run pauses and tries
           again later; pauses are not counted as retries.

  python3 run_llm.py pilot_plan.csv --base ../pilot_runs --pilot --budget 10   # trial rows, not counted
  python3 run_llm.py runs.csv --base ../runs --budget 150                      # registered rows (prompts frozen)
  python3 run_llm.py runs.csv --base ../runs --route chatgpt                   # same, on the ChatGPT plan
  python3 run_llm.py runs.csv --base ../dry --dry-run                          # render every prompt, no API call
  python3 run_llm.py --signin | --whoami | --signout [--forget] | --where      # ChatGPT route credentials
  python3 run_llm.py --preflight OUT.json --route chatgpt                      # account, model and one short call
  python3 run_llm.py --serve .. --cap 160                                      # launcher: pilot, then control file
  python3 run_llm.py --selftest                                                # local mock servers, no network

Transcription rule (how an artifact file is made from a response): the IDEF0 model is the whole response text;
the GRAFCET JSON and the ST code are the contents of the fenced code blocks of the response, in order, joined by
a blank line, or the whole response text when it has no fenced block (an unclosed fence runs to the end). Nothing
else is changed. The full response is kept next to the artifact (raw/).

Credentials (the API key, the ChatGPT tokens) are never printed, logged, or written into the run folders. The
ChatGPT tokens are kept in the credential folder (--where prints it) with owner-only permissions.
"""
import argparse
import base64
import csv
import datetime
import hashlib
import hmac
import html
import http.client
import http.server
import json
import os
import platform
import random
import re
import secrets
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
SELF_SHA256 = hashlib.sha256(open(os.path.abspath(__file__), 'rb').read()).hexdigest()

SETTINGS = {
    'api': 'OpenAI Responses API',
    'endpoint': 'https://api.openai.com/v1/responses',
    'model': 'gpt-6.1-sol',
    'reasoning_effort': 'medium',
    'max_output_tokens': 64000,
    'store': False,
    'system_message': None,
    'tools': None,
    'sampling': 'provider default; temperature and top_p are not sent (not supported for this model)',
    'transcription_rule': 'v1 (see the module docstring)',
}
# US$ per 1M tokens, OpenAI model page of gpt-6.1-sol (retrieved 2026-11-13): input 2.00, cached input 0.10,
# output 10.00, cache writes 2.50. The cost guard charges uncached input at the cache-write rate (upper bound).
PRICES = {'input': 2.00, 'cached_input': 0.10, 'output': 10.00, 'cache_write': 2.50}
RESERVE = {'workflow': 1.50, 'baseline': 0.40}   # cost reserved for a row before its first call (upper bound)
TEMPERATURE_FIELD = 'not settable (reasoning effort medium)'
KEYCHAIN_ITEM = 'openai-api-key'
RETRY_CODES = {408, 409, 429, 500, 502, 503, 504}
MAX_ATTEMPTS = 6
TIMEOUT_S = 900
PREFLIGHT_PROMPT = 'Reply with the single word OK.'

# ChatGPT plan usage through Sign in with ChatGPT (developers.openai.com/siwc/token-sharing-open-source,
# retrieved 2026-11-13): sign-in, token refresh, revocation, model list, Responses requirements, error codes.
APP = 'model-first-plc-agent-ai'
AGENT_NAME = APP
UA = '%s/2 (Python %s; %s)' % (APP, platform.python_version(), sys.platform)
CONF = {'auth_base': 'https://auth.openai.com', 'api_base': 'https://api.openai.com/v1', 'cred_dir': None,
        'open_browser': None, 'pause_s': 1800.0, 'callback_ports': range(1455, 1465)}
RESOURCE = 'https://api.openai.com/v1'
SCOPES = 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct'
PLAN_SCOPE = 'chatgpt.tokens.use.direct'
REFRESH_MARGIN_S = 300
USAGE_LIMIT = 'subscription_sharing_usage_limit_exceeded'
UNSUPPORTED = 'subscription_sharing_unsupported_capability'
TERMINAL_REFRESH = {'invalid_grant', 'invalid_refresh_token', 'token_expired', 'refresh_token_expired',
                    'refresh_token_invalidated', 'refresh_token_reused'}
PLAN_RETRYABLE = {'subscription_sharing_usage_unavailable', 'subscription_sharing_user_unavailable', 'server_error',
                  'rate_limit_exceeded'}
PLAN_EXPLAIN = {
    'subscription_sharing_user_not_eligible': 'ChatGPT plan usage is not available for this account, workspace or '
                                              'policy (the route needs a Plus or Pro plan)',
    'subscription_sharing_route_not_supported': 'this endpoint is not supported for ChatGPT plan usage',
    'subscription_sharing_invalid_user': 'the ChatGPT account could not be validated; sign in again',
    'chatpass_v2_scope_not_authorized': 'the sign-in does not authorize plan usage; sign in again and keep the '
                                        'option to use the ChatGPT plan',
    'chatpass_v2_invalid_authorization_context': 'the sign-in does not authorize plan usage; sign in again',
}

LANES = {
    'workflow': [('A1', [('A1_1_idef0', 'a1_idef0', 'text'), ('A1_2_grafcet', 'a1_grafcet_json', 'block'),
                         ('A1_3_st', 'st_code', 'block')]),
                 ('A2', [('A2_1_idef0', 'a2_idef0', 'text'), ('A2_2_grafcet', 'a2_grafcet_json', 'block'),
                         ('A2_3_st', 'a2_st_code', 'block')])],
    'baseline': [('B', [('B_st', 'st_code', 'block')])],
}
IDEF0_COL = {'A1': 'a1_idef0', 'A2': 'a2_idef0'}
GRAFCET_COL = {'A1': 'a1_grafcet_json', 'A2': 'a2_grafcet_json'}


class Fatal(Exception):
    """A configuration or authorization problem: stop the whole run instead of spending the budget."""


class Unsupported(Fatal):
    def __init__(self, param, msg):
        Fatal.__init__(self, msg)
        self.param = param


class Budget(Exception):
    pass


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def settings_for(route='api', omit_reasoning=False):
    """Registered settings of an access route; their SHA-256 goes into every record."""
    s = dict(SETTINGS)
    if route == 'chatgpt':
        s.update({'api': 'OpenAI Responses API, ChatGPT plan usage (Sign in with ChatGPT)',
                  'access': 'ChatGPT plan (OAuth access token)', 'stream': True, 'max_output_tokens': None,
                  'max_output_tokens_note': 'not accepted on this route; the model maximum applies',
                  'usage_limit_rule': 'pause, then try again; pauses are not retries'})
        if omit_reasoning:
            s['reasoning_effort'] = ('not sent (field not accepted on this route); the effort reported by the API '
                                     'was medium in the preflight')
    else:
        s.update({'access': 'OpenAI API key', 'stream': False})
    return s


def settings_digest(settings=None):
    s = settings if settings is not None else settings_for('api')
    return sha(json.dumps(s, sort_keys=True) + json.dumps(PRICES, sort_keys=True))


# ---------------------------------------------------------------- prompts and transcription

def read(p):
    return open(p, encoding='utf-8').read().strip()


def write_atomic(path, text):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(text)
    os.replace(tmp, path)


def render(template, task, idef0_text=None, grafcet_text=None):
    """Same text as render_prompt.py prints (without the final newline of print)."""
    text = read(os.path.join(HERE, 'prompts', 'templates', template + '.md'))
    fills = {'{TASK_CARD}': read(os.path.join(HERE, 'prompts', 'tasks', task + '.md')),
             '{SCHEMA}': read(os.path.join(HERE, 'prompts', 'templates', '_schema.md'))}
    if '{IDEF0_MODEL}' in text:
        fills['{IDEF0_MODEL}'] = idef0_text.strip()
    if '{GRAFCET_JSON}' in text:
        fills['{GRAFCET_JSON}'] = grafcet_text.strip()
    for k, v in fills.items():
        text = text.replace(k, v)
    return text


FENCE = re.compile(r'^[ \t]*(```|~~~)')


def transcribe(text):
    """Contents of the fenced code blocks in order, joined by a blank line; the whole text without fences."""
    blocks, cur, marker = [], None, None
    for ln in text.split('\n'):
        m = FENCE.match(ln)
        if cur is None:
            if m:
                cur, marker = [], m.group(1)
        elif m and m.group(1) == marker and ln.strip() == marker:
            blocks.append('\n'.join(cur))
            cur = None
        else:
            cur.append(ln)
    if cur is not None:
        blocks.append('\n'.join(cur))
    if not blocks:
        return text.strip()
    return '\n\n'.join(b.strip('\n') for b in blocks).strip()


# ---------------------------------------------------------------- credentials

def cred_dir():
    if CONF['cred_dir']:
        return CONF['cred_dir']
    if sys.platform == 'win32':
        return os.path.join(os.environ.get('APPDATA') or os.path.expanduser('~'), APP)
    return os.path.join(os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config'), APP)


def cred_path(name):
    return os.path.join(cred_dir(), name)


def load_json(p):
    try:
        return json.load(open(p, encoding='utf-8'))
    except (OSError, ValueError):
        return None


def write_private(path, text):
    """Atomic write with owner-only permissions (0600 on Unix; the user profile folder on Windows)."""
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    if os.name == 'posix':
        try:
            os.chmod(d, 0o700)
        except OSError:
            pass
    fd, tmp = tempfile.mkstemp(dir=d, prefix='.tmp-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(text)
        if os.name == 'posix':
            os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise


def host_id():
    p = cred_path('host.json')
    h = load_json(p) or {}
    if not h.get('ext_agent_host_id'):
        h = {'ext_agent_host_id': uuid.uuid4().urn, 'created_utc': now()}
        write_private(p, json.dumps(h, indent=1))
    else:
        # Local host-ID compatibility fix: retain the UUID, add its URI prefix.
        value = h['ext_agent_host_id']
        if isinstance(value, str):
            try:
                legacy_uuid = uuid.UUID(value)
            except ValueError:
                pass  # Preserve other supported identifiers (JWK URI / did:key).
            else:
                if value.lower() == str(legacy_uuid):
                    h['ext_agent_host_id'] = legacy_uuid.urn
                    write_private(p, json.dumps(h, indent=1))
    return h['ext_agent_host_id']


def mask(email):
    if not email or '@' not in email:
        return 'an account without e-mail'
    u, d = email.split('@', 1)
    return u[:2] + '***@' + d


def api_key():
    k = os.environ.get('OPENAI_API_KEY', '').strip()
    if k:
        return k, 'environment variable OPENAI_API_KEY'
    if sys.platform == 'darwin' and shutil.which('security'):
        p = subprocess.run(['security', 'find-generic-password', '-s', KEYCHAIN_ITEM, '-w'],
                           capture_output=True, text=True)
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.strip(), 'macOS keychain item %s' % KEYCHAIN_ITEM
    f = cred_path('openai_api_key')
    if os.path.exists(f):
        k = open(f, encoding='utf-8').read().strip()
        if k:
            return k, 'credential file in %s' % cred_dir()
    raise Fatal('no API key: run the setup step (launcher.py setup), or set OPENAI_API_KEY')


# ---------------------------------------------------------------- HTTP

_MODE = {'transport': 'urllib'}


def _q(v):
    return '"' + str(v).replace('\\', '\\\\').replace('"', '\\"') + '"'


def _use_curl_instead(e):
    if isinstance(getattr(e, 'reason', None), ssl.SSLError) and shutil.which('curl'):
        if _MODE['transport'] != 'curl':
            print('note: Python cannot verify TLS certificates here; using curl for the network calls')
        _MODE['transport'] = 'curl'
        return True
    return False


def _curl_request(method, url, body, headers, timeout):
    """Fallback when Python has no CA certificates; secrets go to curl on standard input, not argv."""
    with tempfile.TemporaryDirectory() as d:
        hf = os.path.join(d, 'headers.txt')
        cfg = ['url = ' + _q(url), 'request = ' + _q(method)]
        cfg += ['header = ' + _q('%s: %s' % kv) for kv in headers.items()]
        if body is not None:
            pf = os.path.join(d, 'body')
            open(pf, 'wb').write(body)
            cfg.append('data-binary = ' + _q('@' + pf))
        cfg += ['dump-header = ' + _q(hf), 'silent', 'show-error', 'max-time = %d' % timeout,
                'write-out = "\\n%{http_code}"']
        p = subprocess.run(['curl', '--config', '-'], input=('\n'.join(cfg) + '\n').encode('utf-8'),
                           capture_output=True)
        if p.returncode != 0:
            raise OSError('curl: ' + p.stderr.decode('utf-8', 'replace').strip()[-300:])
        text, _, code = p.stdout.decode('utf-8', 'replace').rpartition('\n')
        hdr = {}
        if os.path.exists(hf):
            for ln in open(hf, encoding='utf-8', errors='replace'):
                if ':' in ln:
                    k, v = ln.split(':', 1)
                    hdr[k.strip().lower()] = v.strip()
        return int(code or 0), text, hdr


def http_request(method, url, body=None, headers=None, timeout=60):
    """(status, text, headers); urllib first, curl when Python has no CA certificates."""
    hdrs = {'User-Agent': UA}
    hdrs.update(headers or {})
    if _MODE['transport'] == 'urllib':
        req = urllib.request.Request(url, data=body, method=method, headers=hdrs)
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=ssl.create_default_context()) as r:
                return r.status, r.read().decode('utf-8', 'replace'), {k.lower(): v for k, v in r.headers.items()}
        except urllib.error.HTTPError as e:
            hdr = {k.lower(): v for k, v in (e.headers.items() if e.headers else [])}
            return e.code, e.read().decode('utf-8', 'replace'), hdr
        except urllib.error.URLError as e:
            if not _use_curl_instead(e):
                raise
    return _curl_request(method, url, body, hdrs, timeout)


def get_json(url, headers=None, timeout=60):
    code, text, _ = http_request('GET', url, None, dict({'Accept': 'application/json'}, **(headers or {})), timeout)
    if code != 200:
        raise OSError('HTTP %s from %s' % (code, url))
    return json.loads(text)


def form(d):
    return urllib.parse.urlencode(d).encode('ascii')


FORM_HEADERS = {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'}


def error_fields(text):
    """(code, param, message) of an API or OAuth error body."""
    try:
        b = json.loads(text)
    except (TypeError, ValueError):
        return None, None, (text or '')[:200]
    if not isinstance(b, dict):
        return None, None, str(b)[:200]
    e = b.get('error')
    if isinstance(e, dict):
        return e.get('code'), e.get('param'), e.get('message')
    if isinstance(e, str):
        return e, None, b.get('error_description')
    return None, None, b.get('detail')


def post(url, payload, key, timeout=TIMEOUT_S):
    return http_request('POST', url, json.dumps(payload).encode('utf-8'),
                        {'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'}, timeout)


def call_api(payload, key, endpoint, log):
    """One response. Retries only when no response was received (network, 408/409/429/5xx, failed status)."""
    last = ''
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            code, text, hdr = post(endpoint, payload, key)
        except (OSError, urllib.error.URLError) as e:
            code, text, hdr = None, str(e), {}
        if code == 200:
            try:
                data = json.loads(text)
            except ValueError:
                data = None
            if isinstance(data, dict) and data.get('status') in ('completed', 'incomplete'):
                return data, attempt
            last = 'status %s' % (data.get('status') if isinstance(data, dict) else 'unreadable body')
        elif code is not None and code not in RETRY_CODES:
            raise Fatal('HTTP %d from the API: %s' % (code, text[:400]))
        else:
            last = 'HTTP %s %s' % (code, text[:200])
        wait = min(300.0, 10.0 * 2 ** (attempt - 1))
        try:
            wait = max(wait, float(hdr.get('retry-after', 0)))
        except ValueError:
            pass
        if attempt < MAX_ATTEMPTS:
            log('  retry %d/%d in %.0f s (%s)' % (attempt, MAX_ATTEMPTS - 1, wait, last.strip()[:120]))
            time.sleep(wait if not os.environ.get('RUN_LLM_FAST_RETRY') else 0.05)
    raise OSError('no response after %d attempts: %s' % (MAX_ATTEMPTS, last))


# ---------------------------------------------------------------- streamed responses (ChatGPT route)

def collect_stream(lines):
    """Read server-sent events of a streamed response: deltas, and the response.completed, .incomplete or
    .failed event. A stream that ends without one of them was interrupted (no response)."""
    res = {'terminal': None, 'final': None, 'error': None, 'deltas': [], 'events': 0, 'interrupted': None}
    state = {'event': None, 'data': []}

    def dispatch():
        payload = '\n'.join(state['data'])
        ev = state['event']
        state['event'], state['data'] = None, []
        if not payload:
            return
        try:
            obj = json.loads(payload)
        except ValueError:
            return
        if not isinstance(obj, dict):
            return
        typ = obj.get('type') or ev
        res['events'] += 1
        if typ == 'response.output_text.delta':
            res['deltas'].append(obj.get('delta') or '')
        elif typ in ('response.completed', 'response.incomplete', 'response.failed'):
            res['terminal'] = typ.split('.', 1)[1]
            res['final'] = obj.get('response') if isinstance(obj.get('response'), dict) else {}
            if typ == 'response.failed':
                res['error'] = res['final'].get('error') or {}
        elif typ == 'error':
            res['terminal'] = 'error'
            res['error'] = obj.get('error') if isinstance(obj.get('error'), dict) else obj

    try:
        for raw in lines:
            line = (raw.decode('utf-8', 'replace') if isinstance(raw, bytes) else raw).rstrip('\r\n')
            if line == '':
                dispatch()
            elif line.startswith(':'):
                continue
            else:
                field, _, value = line.partition(':')
                if value.startswith(' '):
                    value = value[1:]
                if field == 'event':
                    state['event'] = value
                elif field == 'data':
                    state['data'].append(value)
        dispatch()
    except (OSError, http.client.HTTPException, ValueError) as e:
        res['interrupted'] = '%s: %s' % (type(e).__name__, e)
    return res


def _stream_curl(url, body, headers, timeout):
    marker = b'__RUN_LLM_HTTP_STATUS__'
    with tempfile.TemporaryDirectory() as d:
        pf = os.path.join(d, 'body')
        open(pf, 'wb').write(body)
        cfg = ['url = ' + _q(url), 'request = "POST"'] + ['header = ' + _q('%s: %s' % kv) for kv in headers.items()]
        cfg += ['data-binary = ' + _q('@' + pf), 'silent', 'show-error', 'no-buffer', 'speed-limit = 1',
                'speed-time = %d' % timeout, 'write-out = "\\n%s%%{http_code}\\n"' % marker.decode('ascii')]
        p = subprocess.Popen(['curl', '--config', '-'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE)
        p.stdin.write(('\n'.join(cfg) + '\n').encode('utf-8'))
        p.stdin.close()
        st = {'code': None, 'sse': None, 'other': []}

        def lines():
            for raw in p.stdout:
                if raw.startswith(marker):
                    try:
                        st['code'] = int(raw[len(marker):].strip() or 0)
                    except ValueError:
                        pass
                    continue
                if st['sse'] is None and raw.strip():
                    st['sse'] = raw.lstrip().startswith((b'event:', b'data:', b':'))
                if st['sse'] is False:
                    st['other'].append(raw)
                    continue
                yield raw

        res = collect_stream(lines())
        err = p.stderr.read().decode('utf-8', 'replace')
        p.wait()
        if st['code'] in (None, 0):
            raise OSError('curl: ' + err.strip()[-300:])
        if st['code'] == 200 and st['sse'] is not False:
            return 200, '', res
        return st['code'], b''.join(st['other']).decode('utf-8', 'replace'), None


def stream_request(url, payload, token, timeout=TIMEOUT_S):
    """POST a streamed request. Returns (status, error text, collect_stream result or None)."""
    body = json.dumps(payload).encode('utf-8')
    hdrs = {'User-Agent': UA, 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json',
            'Accept': 'text/event-stream'}
    if _MODE['transport'] == 'urllib':
        req = urllib.request.Request(url, data=body, method='POST', headers=hdrs)
        try:
            r = urllib.request.urlopen(req, timeout=timeout, context=ssl.create_default_context())
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode('utf-8', 'replace'), None
        except urllib.error.URLError as e:
            if not _use_curl_instead(e):
                raise
        else:
            with r:
                return r.status, '', collect_stream(r)
    return _stream_curl(url, body, hdrs, timeout)


def finalize(res):
    """The response object of response.completed or .incomplete; text from the deltas if it carries none."""
    data = dict(res.get('final') or {})
    data.setdefault('status', res['terminal'])
    text_final = output_text(data) if data.get('output') else ''
    deltas = ''.join(res['deltas'])
    if not text_final and deltas:
        data['output'] = [{'type': 'message', 'role': 'assistant',
                           'content': [{'type': 'output_text', 'text': deltas}]}]
    data['x_runner'] = {'stream_events': res['events'],
                        'text_source': 'response' if text_final else ('deltas' if deltas else 'none'),
                        'delta_mismatch': bool(text_final and deltas and text_final != deltas)}
    return data


class PauseGate:
    """All workers wait while the ChatGPT plan's usage limit is reached; they try again after the pause."""

    def __init__(self, seconds, log=print, on_trip=None):
        self.seconds, self.log, self.on_trip = seconds, log, on_trip
        self.cv = threading.Condition()
        self.until = 0.0
        self.count = 0

    def wait(self):
        with self.cv:
            while True:
                left = self.until - time.time()
                if left <= 0:
                    return
                self.cv.wait(min(left, 60.0))

    def trip(self, why):
        with self.cv:
            t = time.time()
            if t < self.until:
                return False
            self.until = t + self.seconds
            self.count += 1
            rec = {'time_utc': now(), 'pause_s': self.seconds, 'reason': why, 'n': self.count}
        self.log('ChatGPT plan usage limit reached (%s): pausing %.0f min, then trying again '
                 '(ChatGPT Settings > Usage shows the limits)' % (why, self.seconds / 60.0))
        if self.on_trip:
            self.on_trip(rec)
        return True


# ---------------------------------------------------------------- ID token check (RS256, ES256)

def b64u_enc(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode('ascii')


def b64u_dec(s):
    s = s.encode('ascii') if isinstance(s, str) else s
    return base64.urlsafe_b64decode(s + b'=' * (-len(s) % 4))


def _b64int(s):
    return int.from_bytes(b64u_dec(s), 'big')


_SHA256_DIGESTINFO = bytes.fromhex('3031300d060960864801650304020105000420')


def _rsa_em(k, msg):
    t = _SHA256_DIGESTINFO + hashlib.sha256(msg).digest()
    return b'\x00\x01' + b'\xff' * (k - len(t) - 3) + b'\x00' + t


def rsa_verify(n, e, msg, sig):
    """RSASSA-PKCS1-v1_5 with SHA-256."""
    k = (n.bit_length() + 7) // 8
    if len(sig) != k or k < 62:
        return False
    s = int.from_bytes(sig, 'big')
    if s >= n:
        return False
    return hmac.compare_digest(pow(s, e, n).to_bytes(k, 'big'), _rsa_em(k, msg))


_P = 2 ** 256 - 2 ** 224 + 2 ** 192 + 2 ** 96 - 1
_A = _P - 3
_B = int('5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b', 16)
_N = int('ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551', 16)
_G = (int('6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296', 16),
      int('4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5', 16))


def _ec_add(p, q):
    if p is None:
        return q
    if q is None:
        return p
    if p[0] == q[0] and (p[1] + q[1]) % _P == 0:
        return None
    if p == q:
        lam = (3 * p[0] * p[0] + _A) * pow(2 * p[1], -1, _P) % _P
    else:
        lam = (q[1] - p[1]) * pow(q[0] - p[0], -1, _P) % _P
    x = (lam * lam - p[0] - q[0]) % _P
    return x, (lam * (p[0] - x) - p[1]) % _P


def _ec_mul(k, p):
    r = None
    while k:
        if k & 1:
            r = _ec_add(r, p)
        p = _ec_add(p, p)
        k >>= 1
    return r


def ecdsa_verify(x, y, msg, sig):
    """ECDSA on P-256 with SHA-256; sig is r || s (64 bytes) as in JWS."""
    if len(sig) != 64 or not (0 <= x < _P and 0 <= y < _P):
        return False
    if (y * y - (x ** 3 + _A * x + _B)) % _P != 0:
        return False
    r, s = int.from_bytes(sig[:32], 'big'), int.from_bytes(sig[32:], 'big')
    if not (1 <= r < _N and 1 <= s < _N):
        return False
    z = int.from_bytes(hashlib.sha256(msg).digest(), 'big')
    w = pow(s, -1, _N)
    pt = _ec_add(_ec_mul(z * w % _N, _G), _ec_mul(r * w % _N, (x, y)))
    return pt is not None and pt[0] % _N == r


def jwt_verify(token, jwks):
    """Header and claims of a JWT whose signature matches a key of the JWKS (RS256 or ES256)."""
    try:
        h64, p64, s64 = token.split('.')
        header, claims, sig = json.loads(b64u_dec(h64)), json.loads(b64u_dec(p64)), b64u_dec(s64)
    except (AttributeError, ValueError, TypeError):
        raise Fatal('the ID token is malformed')
    alg, kid = header.get('alg'), header.get('kid')
    if alg not in ('RS256', 'ES256'):
        raise Fatal('the ID token is signed with %s, which this runner cannot check' % alg)
    msg = (h64 + '.' + p64).encode('ascii')
    for k in (jwks or {}).get('keys', []):
        if kid is not None and k.get('kid') != kid:
            continue
        try:
            if alg == 'RS256' and k.get('kty') == 'RSA' and rsa_verify(_b64int(k['n']), _b64int(k['e']), msg, sig):
                return header, claims
            if alg == 'ES256' and k.get('kty') == 'EC' and k.get('crv') == 'P-256' and \
                    ecdsa_verify(_b64int(k['x']), _b64int(k['y']), msg, sig):
                return header, claims
        except (KeyError, ValueError, TypeError):
            continue
    raise Fatal('the ID token signature does not match the published keys')


def validate_id_token(token, jwks, issuer, client_id, nonce=None, leeway=300):
    _, c = jwt_verify(token, jwks)
    if c.get('iss') != issuer:
        raise Fatal('ID token issuer %r is not %r' % (c.get('iss'), issuer))
    aud = c.get('aud')
    if client_id not in (aud if isinstance(aud, list) else [aud]):
        raise Fatal('ID token audience does not match the issued client ID')
    try:
        exp = float(c.get('exp'))
    except (TypeError, ValueError):
        raise Fatal('ID token has no expiry')
    if time.time() > exp + leeway:
        raise Fatal('ID token has expired')
    if nonce is not None and c.get('nonce') != nonce:
        raise Fatal('ID token nonce does not match this sign-in')
    if not c.get('sub'):
        raise Fatal('ID token has no subject')
    return c


def discovery():
    return get_json(CONF['auth_base'] + '/.well-known/openid-configuration')


def _email(claims):
    prof = claims.get('https://api.openai.com/profile') or {}
    return claims.get('email') or (prof.get('email') if isinstance(prof, dict) else None)


# ---------------------------------------------------------------- Sign in with ChatGPT

class _Box:
    def __init__(self):
        self.ev, self.val = threading.Event(), None

    def put(self, v):
        if not self.ev.is_set():
            self.val = v
            self.ev.set()

    def wait(self, t):
        return self.val if self.ev.wait(t) else None


def _loopback(box):
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            u = urllib.parse.urlsplit(self.path)
            if u.path != '/auth/callback':
                self.send_response(404)
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query, keep_blank_values=True).items()}
            box.put(q)
            if 'code' in q and 'error' not in q:
                msg = '登入完成，可以關閉此頁，回到執行程式的視窗。Sign-in finished; you can close this page.'
            else:
                msg = '登入沒有完成（%s）。請回到執行程式的視窗。Sign-in not finished.' % html.escape(q.get('error', '?'))
            body = ('<!doctype html><meta charset="utf-8"><title>IJEE PLC runner</title><p>%s</p>' % msg).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    class S(http.server.ThreadingHTTPServer):
        allow_reuse_address = os.name != 'nt'   # on Windows the option would let another program share the port
        daemon_threads = True

    ports = list(CONF['callback_ports'])
    for port in ports:
        try:
            srv = S(('127.0.0.1', port), H)
            break
        except OSError:
            continue
    else:
        raise Fatal('no free local port between %d and %d for the sign-in answer' % (ports[0], ports[-1]))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


def open_browser(url):
    if CONF['open_browser']:
        return CONF['open_browser'](url)
    try:
        return webbrowser.open(url)
    except Exception:   # noqa: BLE001 - the address is also printed
        return False


def signin(log=print, timeout_s=600):
    """Sign in with ChatGPT in the system browser and keep the plan-usage tokens in the credential folder."""
    host = host_id()
    prof = load_json(cred_path('chatgpt.json')) or {}
    returning = bool(prof.get('client_id'))
    verifier = b64u_enc(secrets.token_bytes(32))
    challenge = b64u_enc(hashlib.sha256(verifier.encode('ascii')).digest())
    state, nonce = b64u_enc(secrets.token_bytes(24)), b64u_enc(secrets.token_bytes(24))
    box = _Box()
    srv, port = _loopback(box)
    redirect = 'http://127.0.0.1:%d/auth/callback' % port
    q = {'response_type': 'code', 'client_id': prof['client_id'] if returning else 'dynamic_agent_client',
         'redirect_uri': redirect, 'scope': SCOPES, 'resource': RESOURCE, 'state': state, 'nonce': nonce,
         'code_challenge': challenge, 'code_challenge_method': 'S256', 'ext_agent_host_id': host}
    if returning:
        if prof.get('id_token'):
            q['id_token_hint'] = prof['id_token']
        if prof.get('email'):
            q['login_hint'] = prof['email']
    else:
        q['agent_name_hint'] = AGENT_NAME
    url = CONF['auth_base'] + '/api/accounts/authorize?' + urllib.parse.urlencode(q)
    try:
        log('A browser window opens for the ChatGPT sign-in (waiting up to %d minutes).' % (timeout_s // 60))
        if not open_browser(url):
            print('The browser did not open; open this address in a browser on this computer:\n' + url, flush=True)
        got = box.wait(timeout_s)
    finally:
        srv.shutdown()
        srv.server_close()
    if got is None:
        raise Fatal('no answer from the browser within %d minutes; run the sign-in again' % (timeout_s // 60))
    if got.get('error'):
        raise Fatal('the sign-in was not completed in the browser (%s)' % got['error'])
    if not hmac.compare_digest(str(got.get('state', '')).encode('utf-8'), state.encode('ascii')):
        raise Fatal('the browser answer does not belong to this sign-in (state); run it again')
    issued = got.get('client_id')
    if returning:
        if issued and issued != prof['client_id']:
            raise Fatal('the browser returned another client registration; the sign-in was rejected')
        client_id = prof['client_id']
    else:
        if not issued:
            raise Fatal('the registration was not completed (no client ID issued); run the sign-in again')
        client_id = issued
    if not got.get('code'):
        raise Fatal('the browser answer has no authorization code')
    code, text, _ = http_request('POST', CONF['auth_base'] + '/api/accounts/oauth/token', form({
        'grant_type': 'authorization_code', 'client_id': client_id, 'code': got['code'],
        'code_verifier': verifier, 'redirect_uri': redirect, 'resource': RESOURCE}), FORM_HEADERS)
    try:
        tok = json.loads(text)
    except ValueError:
        tok = {}
    if code != 200 or not isinstance(tok, dict) or not tok.get('access_token'):
        ecode, _, msg = error_fields(text)
        raise Fatal('the token exchange failed (HTTP %s%s); run the sign-in again' % (code, ', ' + str(ecode or msg)
                                                                                    if (ecode or msg) else ''))
    disc = discovery()
    claims = validate_id_token(tok.get('id_token'), get_json(disc['jwks_uri']), disc['issuer'], client_id, nonce)
    scopes = tok.get('scope') or ''
    if PLAN_SCOPE not in scopes.split():
        raise Fatal('ChatGPT plan usage was not granted (scope %s missing); sign in again and keep the option '
                    'to use the ChatGPT plan on the consent page' % PLAN_SCOPE)
    if not tok.get('refresh_token'):
        raise Fatal('no refresh token was issued (offline access not granted); sign in again')
    if returning and prof.get('subject') and claims['sub'] != prof['subject']:
        raise Fatal('this is a different ChatGPT account from the earlier sign-in; to switch accounts, run the '
                    'sign-out with --forget first')
    exp_in = int(tok.get('expires_in') or 3600)
    rec = {'email': _email(claims), 'issuer': disc['issuer'], 'subject': claims['sub'], 'client_id': client_id,
           'ext_agent_host_id': host, 'id_token': tok.get('id_token'), 'access_token': tok['access_token'],
           'refresh_token': tok['refresh_token'], 'token_type': tok.get('token_type'), 'expires_in': exp_in,
           'expires_at': time.time() + exp_in, 'scopes': scopes, 'earliest_refresh_at': tok.get('earliest_refresh_at'),
           'saved_at': now()}
    write_private(cred_path('chatgpt.json'), json.dumps(rec, indent=1))
    return {'account': mask(rec['email']), 'client_id': client_id[:12] + '...', 'returning': returning}


def signout(log=print, forget=False):
    """Revoke the refresh token, clear the tokens; with forget, drop the client registration as well."""
    p = cred_path('chatgpt.json')
    prof = load_json(p)
    if not prof:
        log('not signed in with ChatGPT')
        return True
    revoked = None
    if prof.get('refresh_token'):
        revoked = False
        try:
            ep = discovery().get('revocation_endpoint')
            for attempt in range(3):
                if not ep:
                    break
                code, _, _ = http_request('POST', ep, form({'token': prof['refresh_token'],
                                                            'token_type_hint': 'refresh_token',
                                                            'client_id': prof['client_id']}), FORM_HEADERS)
                if code == 200:
                    revoked = True
                    break
                if code is not None and code < 500:
                    break
                time.sleep(2 ** attempt if not os.environ.get('RUN_LLM_FAST_RETRY') else 0.01)
        except (OSError, ValueError, KeyError):
            pass
    if forget:
        os.remove(p)
    else:
        keep = {k: prof.get(k) for k in ('email', 'issuer', 'subject', 'client_id', 'ext_agent_host_id', 'id_token')}
        keep['signed_out_utc'] = now()
        write_private(p, json.dumps(keep, indent=1))
    if revoked is False:
        log('revocation was not confirmed; you can also disconnect the app in ChatGPT Settings')
    return revoked is not False


def whoami():
    prof = load_json(cred_path('chatgpt.json')) or {}
    if not prof.get('access_token'):
        return 'not signed in with ChatGPT'
    until = datetime.datetime.fromtimestamp(prof.get('expires_at', 0), datetime.timezone.utc)
    return 'signed in with ChatGPT as %s (client %s...); access token valid until %s UTC; plan scope %s' % (
        mask(prof.get('email')), (prof.get('client_id') or '')[:12], until.strftime('%Y-%m-%d %H:%M'),
        'granted' if PLAN_SCOPE in (prof.get('scopes') or '').split() else 'missing')


class PlanAuth:
    """Access token of the ChatGPT sign-in, refreshed before it expires (refresh tokens rotate)."""

    def __init__(self, log=print):
        self.path, self.log, self.lock = cred_path('chatgpt.json'), log, threading.Lock()
        self.c = load_json(self.path) or {}
        if not self.c.get('access_token') or not self.c.get('refresh_token'):
            raise Fatal('not signed in with ChatGPT: run the setup step (launcher.py setup) first')
        if PLAN_SCOPE not in (self.c.get('scopes') or '').split():
            raise Fatal('the saved sign-in does not grant ChatGPT plan usage; run the setup step again')

    def describe(self):
        return 'signed in, plan usage granted'

    def secrets(self):
        return [v for v in (self.c.get('access_token'), self.c.get('refresh_token'), self.c.get('id_token')) if v]

    def token(self, force=False):
        with self.lock:
            if force or time.time() > float(self.c.get('expires_at', 0)) - REFRESH_MARGIN_S:
                self._refresh()
            return self.c['access_token']

    def _refresh(self):
        code, text, _ = http_request('POST', CONF['auth_base'] + '/api/accounts/oauth/token', form({
            'grant_type': 'refresh_token', 'client_id': self.c['client_id'], 'refresh_token': self.c['refresh_token'],
            'resource': RESOURCE}), FORM_HEADERS)
        try:
            tok = json.loads(text)
        except ValueError:
            tok = {}
        if code == 200 and isinstance(tok, dict) and tok.get('access_token'):
            new = dict(self.c)
            exp_in = int(tok.get('expires_in') or 3600)
            new.update({'access_token': tok['access_token'],
                        'refresh_token': tok.get('refresh_token') or self.c['refresh_token'],
                        'token_type': tok.get('token_type') or self.c.get('token_type'), 'expires_in': exp_in,
                        'expires_at': time.time() + exp_in, 'scopes': tok.get('scope') or self.c.get('scopes'),
                        'earliest_refresh_at': tok.get('earliest_refresh_at'), 'saved_at': now()})
            if tok.get('id_token'):
                disc = discovery()
                claims = validate_id_token(tok['id_token'], get_json(disc['jwks_uri']), disc['issuer'],
                                           self.c['client_id'])
                if claims['sub'] != self.c.get('subject'):
                    raise Fatal('the refreshed sign-in belongs to another account; sign in again')
                new['id_token'] = tok['id_token']
            if PLAN_SCOPE not in (new['scopes'] or '').split():
                raise Fatal('the refreshed sign-in no longer grants ChatGPT plan usage; sign in again')
            write_private(self.path, json.dumps(new, indent=1))
            self.c = new
            return
        ecode, _, msg = error_fields(text)
        if ecode in TERMINAL_REFRESH:
            keep = {k: self.c.get(k) for k in ('email', 'issuer', 'subject', 'client_id', 'ext_agent_host_id',
                                               'id_token')}
            write_private(self.path, json.dumps(keep, indent=1))
            self.c = keep
            raise Fatal('the ChatGPT sign-in has expired or was disconnected (%s): run the setup step again; '
                        'finished calls are kept and the run continues where it stopped' % ecode)
        if ecode == 'invalid_client':
            raise Fatal('the client registration was rejected (invalid_client); sign out with --forget and sign in again')
        if code is None or code >= 500 or code in (408, 429):
            raise OSError('token refresh failed for now (HTTP %s)' % code)
        raise Fatal('token refresh failed (HTTP %s %s)' % (code, ecode or msg))


def make_payload(route, messages, prompt, omit_reasoning=False):
    p = {'model': SETTINGS['model'], 'input': messages + [{'role': 'user', 'content': prompt}]}
    if route == 'chatgpt':
        if not omit_reasoning:
            p['reasoning'] = {'effort': SETTINGS['reasoning_effort']}
        p.update({'store': False, 'stream': True})
    else:
        p.update({'reasoning': {'effort': SETTINGS['reasoning_effort']},
                  'max_output_tokens': SETTINGS['max_output_tokens'], 'store': SETTINGS['store']})
    return p


class ApiClient:
    route = 'api'

    def __init__(self, key, endpoint=None):
        self.key, self.endpoint = key, endpoint or CONF['api_base'] + '/responses'   # = SETTINGS['endpoint']
        self.settings = settings_for('api')

    def payload(self, messages, prompt):
        return make_payload('api', messages, prompt)

    def respond(self, payload, log):
        return call_api(payload, self.key, self.endpoint, log)

    def secrets(self):
        return [self.key]


class PlanClient:
    route = 'chatgpt'

    def __init__(self, auth, omit_reasoning=False, gate=None, endpoint=None, pause_is_fatal=False):
        self.auth, self.omit, self.pause_is_fatal = auth, omit_reasoning, pause_is_fatal
        self.gate = gate or PauseGate(CONF['pause_s'])
        self.endpoint = endpoint or CONF['api_base'] + '/responses'
        self.settings = settings_for('chatgpt', omit_reasoning)

    def payload(self, messages, prompt):
        return make_payload('chatgpt', messages, prompt, self.omit)

    def secrets(self):
        return self.auth.secrets()

    def _limit(self, why):
        if self.pause_is_fatal:
            raise Fatal('the ChatGPT plan usage limit is reached now (%s); try again later' % why)
        self.gate.trip(why)

    def respond(self, payload, log):
        """One response. Pauses on the plan's usage limit; retries (counted) only when no response arrived."""
        attempt, refreshed, last = 0, False, ''
        while True:
            self.gate.wait()
            attempt += 1
            try:
                code, etext, res = stream_request(self.endpoint, payload, self.auth.token())
            except (OSError, urllib.error.URLError) as e:
                code, etext, res = None, str(e), None
            if code == 200 and res is not None:
                if res['terminal'] in ('completed', 'incomplete'):
                    return finalize(res), attempt
                err = res.get('error') if isinstance(res.get('error'), dict) else {}
                ecode = err.get('code')
                if ecode == USAGE_LIMIT:
                    self._limit('stream')
                    attempt -= 1
                    continue
                if res['terminal'] is None:
                    last = 'stream ended without response.completed (%s)' % (res.get('interrupted') or 'closed')
                elif ecode in PLAN_RETRYABLE or not ecode:
                    last = 'response.%s %s' % (res['terminal'], ecode or '')
                else:
                    raise Fatal('response.failed: %s %s' % (ecode, PLAN_EXPLAIN.get(ecode, err.get('message') or '')))
            elif code is not None:
                ecode, eparam, msg = error_fields(etext)
                if ecode == USAGE_LIMIT:
                    self._limit('HTTP %d' % code)
                    attempt -= 1
                    continue
                if code == 401 and not refreshed:
                    self.auth.token(force=True)
                    refreshed = True
                    attempt -= 1
                    continue
                if ecode == UNSUPPORTED:
                    raise Unsupported(eparam, 'the ChatGPT plan route does not accept %r (%s)' % (eparam, msg or ''))
                if code in (401, 403) or ecode in PLAN_EXPLAIN:
                    raise Fatal('HTTP %d %s: %s' % (code, ecode or '', PLAN_EXPLAIN.get(ecode, msg or '')))
                if code in RETRY_CODES or ecode in PLAN_RETRYABLE:
                    last = 'HTTP %d %s' % (code, ecode or (msg or '')[:100])
                else:
                    raise Fatal('HTTP %d from the API: %s' % (code, (etext or '')[:400]))
            else:
                last = 'network: %s' % (etext or '')[:160]
            if attempt >= MAX_ATTEMPTS:
                raise OSError('no response after %d attempts: %s' % (MAX_ATTEMPTS, last))
            wait = min(300.0, 10.0 * 2 ** (attempt - 1))
            log('  retry %d/%d in %.0f s (%s)' % (attempt, MAX_ATTEMPTS - 1, wait, last[:120]))
            time.sleep(wait if not os.environ.get('RUN_LLM_FAST_RETRY') else 0.05)


class DryClient:
    def __init__(self, route='api', omit_reasoning=False):
        self.route, self.omit = route, omit_reasoning
        self.settings = settings_for(route, omit_reasoning)

    def payload(self, messages, prompt):
        return make_payload(self.route, messages, prompt, self.omit)

    def secrets(self):
        return []


def output_text(data):
    texts, refusals = [], []
    for item in data.get('output') or []:
        if item.get('type') == 'message':
            parts = []
            for c in item.get('content') or []:
                if c.get('type') == 'output_text':
                    parts.append(c.get('text') or '')
                elif c.get('type') == 'refusal':
                    refusals.append(c.get('refusal') or '')
            if parts:
                texts.append(''.join(parts))
    text = '\n\n'.join(texts)
    if not text and refusals:
        text = '\n'.join(refusals)
    return text


def usage_of(data):
    u = data.get('usage') or {}
    inp = u.get('input_tokens', u.get('prompt_tokens', 0)) or 0
    cached = (u.get('input_tokens_details') or u.get('prompt_tokens_details') or {}).get('cached_tokens') or 0
    out = u.get('output_tokens', u.get('completion_tokens', 0)) or 0
    reasoning = (u.get('output_tokens_details') or u.get('completion_tokens_details') or {}).get('reasoning_tokens') or 0
    return int(inp), int(cached), int(out), int(reasoning)


def cost_of(inp, cached, out):
    uncached = max(PRICES['input'], PRICES['cache_write'])
    return ((inp - cached) * uncached + cached * PRICES['cached_input'] + out * PRICES['output']) / 1e6


# ---------------------------------------------------------------- preflight

def preflight(route, out=None, log=print, omit_reasoning=False, endpoint=None):
    """Account and model check plus one short call with the registered settings (not a sample)."""
    rec = {'time_utc': now(), 'route': route, 'model': SETTINGS['model'], 'runner_sha256': SELF_SHA256,
           'python': platform.python_version(), 'platform': platform.platform(terse=True), 'ok': False}
    try:
        if route == 'chatgpt':
            auth = PlanAuth(log)
            rec['account'] = 'ChatGPT sign-in'
            code = text = None
            for _ in range(2):
                code, text, _h = http_request('GET', CONF['api_base'] + '/models', None,
                                              {'Authorization': 'Bearer ' + auth.token(), 'Accept': 'application/json'})
                if code != 401:
                    break
                auth.token(force=True)
            if code != 200:
                ecode, _, msg = error_fields(text)
                raise Fatal('the model list failed (HTTP %s %s): %s' % (code, ecode or '', PLAN_EXPLAIN.get(ecode, msg)))
            body = json.loads(text)
            models = body.get('models') if isinstance(body.get('models'), list) else body.get('data') or []
            listed = [m.get('slug') or m.get('id') for m in models
                      if isinstance(m, dict) and m.get('visibility', 'list') == 'list']
            client = PlanClient(auth, omit_reasoning, PauseGate(60.0, log), endpoint, pause_is_fatal=True)
        else:
            key, src = api_key()
            rec['account'] = src
            code, text, _h = http_request('GET', CONF['api_base'] + '/models', None, {'Authorization': 'Bearer ' + key})
            if code != 200:
                raise Fatal('the model list failed (HTTP %s): %s' % (code, error_fields(text)[2]))
            listed = [m.get('id') for m in json.loads(text).get('data', []) if isinstance(m, dict)]
            client = ApiClient(key, endpoint)
        rec['models_listed'] = len(listed)
        rec['model_listed'] = SETTINGS['model'] in listed
        if not rec['model_listed']:
            raise Fatal('%s is not offered to this account (listed: %s)' % (SETTINGS['model'], ', '.join(
                str(x) for x in listed[:8]) or 'none'))
        try:
            data, attempts = client.respond(client.payload([], PREFLIGHT_PROMPT), log)
        except Unsupported as e:
            if route != 'chatgpt' or e.param != 'reasoning' or omit_reasoning:
                raise
            rec['reasoning_field'] = 'not accepted on this route; sent again without it'
            omit_reasoning = True
            client = PlanClient(client.auth, True, client.gate, endpoint, pause_is_fatal=True)
            data, attempts = client.respond(client.payload([], PREFLIGHT_PROMPT), log)
        eff = (data.get('reasoning') or {}).get('effort')
        inp, cached, outk, reasoning = usage_of(data)
        rec.update({'model_returned': data.get('model'), 'status': data.get('status'), 'attempts': attempts,
                    'reasoning_effort_reported': eff, 'reply': output_text(data).strip()[:60],
                    'usage': {'input': inp, 'cached': cached, 'output': outk, 'reasoning': reasoning},
                    'omit_reasoning': omit_reasoning, 'settings_sha256': settings_digest(client.settings)})
        if omit_reasoning and eff != SETTINGS['reasoning_effort']:
            raise Fatal('the route does not accept the reasoning field and reports effort %r instead of %r; ask the '
                        'corresponding author before running' % (eff, SETTINGS['reasoning_effort']))
        rec['ok'] = True
        return rec
    except Fatal as e:
        rec['error'] = str(e)
        raise
    finally:
        if out:
            os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
            json.dump(rec, open(out, 'w', encoding='utf-8'), indent=1)


# ---------------------------------------------------------------- one row

class Runner:
    def __init__(self, base, client, budget, dry, log):
        self.base, self.client, self.budget, self.dry, self.log = base, client, budget, dry, log
        self.digest = settings_digest(client.settings)
        self.lock = threading.Lock()
        self.spent = 0.0
        self.reserved = 0.0
        self.calls = 0
        self.row_costs = {'workflow': [], 'baseline': []}
        self.ledger = os.path.join(base, 'llm_ledger.jsonl')
        self.fatal = None

    def reserve(self, cond):
        with self.lock:
            seen = self.row_costs.get(cond) or []
            need = max([RESERVE[cond]] + [1.25 * c for c in seen])
            if self.spent + self.reserved + need > self.budget:
                return 0.0
            self.reserved += need
            return need

    def release(self, amount, cond, row_cost):
        with self.lock:
            self.reserved -= amount
            self.row_costs[cond].append(row_cost)

    def record(self, rec):
        with self.lock:
            self.spent += rec['cost_usd']
            self.calls += 1
            with open(self.ledger, 'a', encoding='utf-8') as f:
                f.write(json.dumps(rec, sort_keys=True) + '\n')

    def run_row(self, row):
        rid, cond, task = row['run_id'], row['condition'], row['task_id']
        rdir = os.path.join(self.base, rid)
        raw = os.path.join(rdir, 'raw')
        done = os.path.join(raw, 'done.json')
        if os.path.exists(done):
            return json.load(open(done, encoding='utf-8')), 0.0
        os.makedirs(raw, exist_ok=True)
        info = {'run_id': rid, 'condition': cond, 'task_id': task, 'calls': [], 'settings_sha256': self.digest,
                'route': self.client.route, 'dry_run': self.dry}
        row_cost = 0.0
        for lane, steps in LANES[cond]:
            messages = []
            for template, col, kind in steps:
                ppath = os.path.join(raw, template + '.prompt.txt')
                opath = os.path.join(raw, template + '.output.txt')
                jpath = os.path.join(raw, template + '.response.json')
                art = os.path.join(self.base, row[col])
                if os.path.exists(jpath) and os.path.exists(opath) and os.path.exists(ppath):
                    try:
                        old = json.load(open(jpath, encoding='utf-8'))
                        prompt, text = open(ppath, encoding='utf-8').read(), open(opath, encoding='utf-8').read()
                    except ValueError:
                        old = None   # an interrupted write: make this call again
                    if old is not None:
                        os.makedirs(os.path.dirname(art), exist_ok=True)
                        write_atomic(art, (text.strip() if kind == 'text' else transcribe(text)) + '\n')
                        messages += [{'role': 'user', 'content': prompt}, {'role': 'assistant', 'content': text}]
                        info['calls'].append({'step': template, 'resumed': True, 'model_returned': old.get('model'),
                                              'status': old.get('status')})
                        continue
                prev = lambda cols: (read(os.path.join(self.base, row[cols[lane]]))
                                     if lane in cols and os.path.exists(os.path.join(self.base, row[cols[lane]]))
                                     else None)
                prompt = render(template, task, prev(IDEF0_COL), prev(GRAFCET_COL))
                payload = self.client.payload(messages, prompt)
                t0 = now()
                if self.dry:
                    data = {'id': 'dry-run', 'model': SETTINGS['model'], 'status': 'completed', 'usage': {},
                            'output': [{'type': 'message', 'content': [
                                {'type': 'output_text', 'text': '[DRY-RUN %s %s]' % (rid, template)}]}]}
                    attempts = 0
                else:
                    data, attempts = self.client.respond(payload, self.log)
                text = output_text(data)
                inp, cached, out, reasoning = usage_of(data)
                api_eq = cost_of(inp, cached, out)
                cost = api_eq if self.client.route == 'api' else 0.0
                write_atomic(ppath, prompt)
                write_atomic(opath, text)
                write_atomic(jpath, json.dumps(data, indent=1))
                os.makedirs(os.path.dirname(art), exist_ok=True)
                write_atomic(art, (text.strip() if kind == 'text' else transcribe(text)) + '\n')
                messages += [{'role': 'user', 'content': prompt}, {'role': 'assistant', 'content': text}]
                inc = (data.get('incomplete_details') or {}).get('reason') if data.get('status') == 'incomplete' else None
                rec = {'run_id': rid, 'lane': lane, 'step': template, 'time_utc_start': t0, 'time_utc_end': now(),
                       'model_requested': SETTINGS['model'], 'model_returned': data.get('model'),
                       'response_id': data.get('id'), 'status': data.get('status'), 'incomplete_reason': inc,
                       'input_tokens': inp, 'cached_tokens': cached, 'output_tokens': out,
                       'reasoning_tokens': reasoning, 'cost_usd': round(cost, 6),
                       'cost_usd_api_equivalent': round(api_eq, 6), 'route': self.client.route,
                       'reasoning_effort_reported': (data.get('reasoning') or {}).get('effort'), 'attempts': attempts,
                       'prompt_sha256': sha(prompt), 'output_sha256': sha(text), 'artifact': row[col],
                       'settings_sha256': self.digest, 'dry_run': self.dry}
                self.record(rec)
                row_cost += cost
                info['calls'].append({k: rec[k] for k in ('step', 'time_utc_start', 'time_utc_end', 'model_returned',
                                                          'status', 'incomplete_reason', 'cost_usd')})
        stamps = [c['time_utc_start'] for c in info['calls'] if 'time_utc_start' in c]
        info['first_call_utc'] = min(stamps) if stamps else None
        info['models_returned'] = sorted({c.get('model_returned') for c in info['calls'] if c.get('model_returned')})
        write_atomic(done, json.dumps(info, indent=1))
        return info, row_cost


def make_client(route, base, log, key=None, endpoint=None, omit_reasoning=False, dry=False):
    if dry:
        return DryClient(route, omit_reasoning)
    if route == 'chatgpt':
        auth = PlanAuth(log)
        log('ChatGPT plan: %s (tokens not shown)' % auth.describe())
        pauses = os.path.join(base, 'pauses.jsonl')

        def on_trip(rec):
            with open(pauses, 'a', encoding='utf-8') as f:
                f.write(json.dumps(rec) + '\n')
        return PlanClient(auth, omit_reasoning, PauseGate(CONF['pause_s'], log, on_trip), endpoint)
    if route != 'api':
        raise Fatal('unknown route %r (api or chatgpt)' % route)
    if key is None:
        key, src = api_key()
        log('API key: %s (not shown)' % src)
    return ApiClient(key, endpoint)


def run_plan(plan, base, budget, workers=4, dry=False, endpoint=None, only=None, log=print, key=None,
             status_cb=None, route='api', omit_reasoning=False):
    rows = list(csv.DictReader(open(plan, encoding='utf-8')))
    rows.sort(key=lambda r: int(r['run_order']))
    if only:
        rows = [r for r in rows if r['run_id'] in only]
    os.makedirs(base, exist_ok=True)
    marker = os.path.join(base, 'DRY_RUN')
    if dry:
        open(marker, 'w').write('outputs in this folder are placeholders\n')
    elif os.path.exists(marker):
        raise Fatal('%s holds dry-run placeholders; use another --base' % base)
    client = make_client(route, base, log, key, endpoint, omit_reasoning, dry)
    if client.route == 'chatgpt':
        budget = float('inf')
    run = Runner(base, client, budget, dry, log)
    mo = client.settings.get('max_output_tokens')
    eff = client.settings['reasoning_effort']
    log('route %s; settings %s; model %s, reasoning effort %s, max output %s; %s; %d rows; %d workers'
        % (client.route, run.digest[:12], SETTINGS['model'], eff if len(eff) < 10 else 'not sent (route default)',
           ('%d tokens' % mo) if mo else 'model maximum',
           ('budget US$%.2f' % budget) if budget != float('inf') else 'counted against the ChatGPT plan',
           len(rows), workers))
    todo = [r for r in rows if not os.path.exists(os.path.join(base, r['run_id'], 'raw', 'done.json'))]
    log('%d rows already done, %d to run' % (len(rows) - len(todo), len(todo)))
    state = {'next': 0, 'done': len(rows) - len(todo), 'stopped': None, 'errors': []}
    slock = threading.Lock()

    def worker():
        while True:
            with slock:
                if state['stopped'] or state['next'] >= len(todo):
                    return
                r = todo[state['next']]
                amount = run.reserve(r['condition']) if not dry else 0.0
                if not dry and amount == 0.0:
                    state['stopped'] = 'budget: US$%.2f spent, next row would exceed US$%.2f' % (run.spent, budget)
                    return
                state['next'] += 1
            t = time.time()
            try:
                _, cost = run.run_row(r)
            except Fatal as e:
                with slock:
                    state['stopped'] = 'fatal: %s' % e
                run.release(amount, r['condition'], 0.0)
                return
            except Exception as e:   # noqa: BLE001 - one row failing must not stop the others
                with slock:
                    state['errors'].append('%s: %s' % (r['run_id'], e))
                log('[error] %s: %s (rerun later to resume this row)' % (r['run_id'], e))
                run.release(amount, r['condition'], 0.0)
                continue
            run.release(amount, r['condition'], cost)
            with slock:
                state['done'] += 1
                msg = '[%d/%d] %s %s %.0f s %s (%d calls)' % (
                    state['done'], len(rows), r['run_id'], r['condition'], time.time() - t,
                    ('US$%.3f, total US$%.2f' % (cost, run.spent)) if client.route == 'api' else 'plan usage',
                    run.calls)
            log(msg)
            if status_cb:
                status_cb({'done': state['done'], 'rows': len(rows), 'spent_usd': round(run.spent, 4),
                           'calls': run.calls, 'last': r['run_id']})

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(max(1, workers))]
    for th in threads:
        th.start()
    while any(th.is_alive() for th in threads):   # short joins keep Ctrl+C working on Windows
        for th in threads:
            th.join(0.5)
    if state['stopped']:
        log('stopped: %s' % state['stopped'])
    if not dry:
        fill_plan(plan, base)
    summary = {'plan': os.path.basename(plan), 'rows': len(rows), 'done': state['done'], 'calls': run.calls,
               'spent_usd': round(run.spent, 4), 'stopped': state['stopped'], 'errors': state['errors'],
               'route': client.route, 'pauses': getattr(getattr(client, 'gate', None), 'count', 0),
               'settings_sha256': run.digest, 'finished_utc': now()}
    log('summary: %s' % json.dumps(summary))
    if state['stopped'] and state['stopped'].startswith('fatal'):
        raise Fatal(state['stopped'])
    return summary


def fill_plan(plan, base):
    """Write model, model_version, temperature and run_date of the finished rows into the plan file."""
    if os.path.basename(plan) == 'run_plan.csv':
        return
    rows = list(csv.DictReader(open(plan, encoding='utf-8')))
    cols = list(rows[0].keys()) if rows else []
    for r in rows:
        done = os.path.join(base, r['run_id'], 'raw', 'done.json')
        if os.path.exists(done):
            info = json.load(open(done, encoding='utf-8'))
            r['model'] = SETTINGS['model']
            r['model_version'] = ';'.join(info.get('models_returned') or []) or SETTINGS['model']
            r['temperature'] = TEMPERATURE_FIELD
            r['run_date'] = (info.get('first_call_utc') or '')[:10]
    tmp = plan + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, plan)


# ---------------------------------------------------------------- launcher (serve mode)

def frozen_ok(exec_dir=HERE):
    """Prompts and this runner unchanged since freezing, and this process runs the frozen runner."""
    p = subprocess.run([sys.executable, os.path.join(exec_dir, 'freeze_prompts.py'), '--verify'],
                       capture_output=True, text=True)
    msg = (p.stdout + p.stderr).strip()
    cur = hashlib.sha256(open(os.path.join(exec_dir, 'run_llm.py'), 'rb').read()).hexdigest()
    if cur != SELF_SHA256:
        return False, 'run_llm.py changed since this process started; start it again'
    return p.returncode == 0, msg


def serve(kit, cap, workers, endpoint=None, poll=30.0, key=None, route='api', omit_reasoning=False):
    """Run the pilot, then follow control/next.json: {"action": "pilot"|"main"|"stop", ...}."""
    exec_dir = os.path.join(kit, 'exec')
    control = os.path.join(kit, 'control')
    os.makedirs(control, exist_ok=True)
    logf = open(os.path.join(control, 'serve.log'), 'a', encoding='utf-8')
    spent = {'usd': 0.0}

    llock = threading.Lock()

    def log(msg):
        line = '%s %s' % (now(), msg)
        with llock:
            print(line, flush=True)
            logf.write(line + '\n')
            logf.flush()

    def status(state, extra=None):
        s = {'time_utc': now(), 'state': state, 'cap_usd': cap, 'spent_usd': round(spent['usd'], 4), 'route': route}
        s.update(extra or {})
        json.dump(s, open(os.path.join(control, 'status.json'), 'w', encoding='utf-8'), indent=1)

    if key is None and route == 'api':
        key, src = api_key()
        log('API key: %s (not shown)' % src)

    def do(action, plan, base, budget, require_frozen):
        budget = min(budget, cap - spent['usd'])
        if budget <= 0:
            log('cap reached; %s not run' % action)
            return
        if require_frozen:
            ok, msg = frozen_ok(exec_dir)
            if not ok:
                log('%s refused: prompts not frozen or changed (%s)' % (action, msg))
                status('waiting', {'refused': action, 'reason': msg})
                return
        status('running', {'action': action, 'plan': plan, 'base': base})
        before = spent['usd']
        plan_path = os.path.join(exec_dir, plan)
        if action == 'pilot':
            os.makedirs(os.path.join(kit, base), exist_ok=True)
            copy = os.path.join(kit, base, 'plan.csv')
            if not os.path.exists(copy):
                shutil.copy2(plan_path, copy)
            plan_path = copy
        try:
            s = run_plan(plan_path, os.path.join(kit, base), budget, workers, endpoint=endpoint,
                         log=log, key=key, route=route, omit_reasoning=omit_reasoning,
                         status_cb=lambda st: status('running', dict(st, action=action, spent_usd=round(
                             before + st['spent_usd'], 4))))
        except Fatal as e:
            log('fatal: %s' % e)
            status('fatal', {'action': action, 'reason': str(e)})
            raise
        spent['usd'] = before + s['spent_usd']
        json.dump(s, open(os.path.join(control, 'summary_%s.json' % base.strip('/').replace('/', '_')), 'w',
                          encoding='utf-8'), indent=1)

    if not os.path.exists(os.path.join(kit, 'pilot_runs', 'PILOT_DONE')):
        do('pilot', 'pilot_plan.csv', 'pilot_runs', 10.0, False)
        open(os.path.join(kit, 'pilot_runs', 'PILOT_DONE'), 'w').write(now() + '\n')
    nxt = os.path.join(control, 'next.json')
    log('waiting for %s (pilot | main | stop)' % nxt)
    status('waiting')
    while True:
        if os.path.exists(nxt):
            try:
                cmd = json.load(open(nxt, encoding='utf-8'))
            except ValueError:
                time.sleep(poll)
                continue
            os.replace(nxt, os.path.join(control, 'next_%s.json' % now().replace(':', '')))
            act = cmd.get('action')
            log('control: %s' % json.dumps(cmd))
            if act == 'stop':
                status('stopped')
                log('stopped by control file')
                return spent['usd']
            if act == 'pilot':
                do('pilot', cmd.get('plan', 'pilot_plan.csv'), cmd.get('base', 'pilot_runs2'),
                   float(cmd.get('budget', 10)), False)
            elif act == 'main':
                if not os.path.exists(os.path.join(exec_dir, 'runs.csv')):
                    shutil.copy2(os.path.join(exec_dir, 'run_plan.csv'), os.path.join(exec_dir, 'runs.csv'))
                do('main', 'runs.csv', cmd.get('base', 'runs'), float(cmd.get('budget', cap)), True)
            else:
                log('unknown action %r ignored' % act)
            status('waiting')
        time.sleep(poll)


# ---------------------------------------------------------------- self-test

SAMPLE_ST = ('PROGRAM Main\n  VAR\n    FillValve AT %QX100.0 : BOOL;\n  END_VAR\n  FillValve := FALSE;\n'
             'END_PROGRAM')


def _mock_reply(req):
    graf = read(os.path.join(HERE, '..', 'nusmv', 'tank_reference.json'))
    first = req['input'][-1]['content'].split('\n', 1)[0]
    if first.startswith('Reply with the single word'):
        return 'OK'
    if 'Structured Text' in first:
        return 'Program:\n```iecst\n' + SAMPLE_ST + '\n```\nNotes follow.'
    if 'GRAFCET' in first:
        return 'Here is the model:\n```json\n' + graf + '\n```\n'
    return '| Node | Function | Inputs | Controls | Outputs | Mechanisms |\n|---|---|---|---|---|---|\n' \
           '| A0 | Control the tank | level | task | valves | PLC |'


def _mock(port_holder, state):
    """Local stand-in for the API-key route (one JSON response per call)."""

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            if self.path.endswith('/models'):
                data = json.dumps({'data': [{'id': 'gpt-6.1-sol'}, {'id': 'gpt-6-luna'}]}).encode('utf-8')
                self.send_response(200 if self.headers.get('Authorization') == 'Bearer sk-selftest-0000' else 401)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            self.send_response(404)
            self.end_headers()

        def do_POST(self):
            n = int(self.headers.get('Content-Length', 0))
            req = json.loads(self.rfile.read(n).decode('utf-8'))
            state['requests'].append(req)
            assert self.headers.get('Authorization') == 'Bearer sk-selftest-0000', 'auth header'
            if state['fail_next']:
                state['fail_next'] -= 1
                self.send_response(429)
                self.send_header('Retry-After', '0')
                self.end_headers()
                self.wfile.write(b'{"error": "rate limited"}')
                return
            if state.get('fatal'):
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'{"error": {"message": "invalid key"}}')
                return
            body = {'id': 'resp_%d' % len(state['requests']), 'object': 'response', 'model': 'gpt-6.1-sol-mock',
                    'status': 'completed', 'reasoning': {'effort': (req.get('reasoning') or {}).get('effort')},
                    'output': [{'type': 'reasoning', 'summary': []},
                               {'type': 'message', 'role': 'assistant',
                                'content': [{'type': 'output_text', 'text': _mock_reply(req)}]}],
                    'usage': {'input_tokens': 1000, 'input_tokens_details': {'cached_tokens': 200},
                              'output_tokens': 3000, 'output_tokens_details': {'reasoning_tokens': 2000}}}
            data = json.dumps(body).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
    port_holder.append(srv.server_address[1])
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def _test_rsa(rng, bits=1024):
    def probable_prime(n):
        if n % 2 == 0:
            return n == 2
        d, s = n - 1, 0
        while d % 2 == 0:
            d, s = d // 2, s + 1
        for _ in range(24):
            x = pow(rng.randrange(2, n - 1), d, n)
            if x in (1, n - 1):
                continue
            for _ in range(s - 1):
                x = pow(x, 2, n)
                if x == n - 1:
                    break
            else:
                return False
        return True

    def prime(b):
        while True:
            c = rng.getrandbits(b) | (1 << (b - 1)) | 1
            if all(c % p for p in (3, 5, 7, 11, 13, 17, 19, 23, 29, 31)) and probable_prime(c):
                return c
    e = 65537
    while True:
        p, q = prime(bits // 2), prime(bits // 2)
        phi = (p - 1) * (q - 1)
        if p != q and phi % e:
            return p * q, e, pow(e, -1, phi)


def _sign_jwt(state, claims):
    alg = state['alg']
    header = {'alg': alg, 'kid': {'RS256': 'rsa1', 'ES256': 'ec1'}.get(alg, 'rsa1'), 'typ': 'JWT'}
    si = b64u_enc(json.dumps(header).encode()) + '.' + b64u_enc(json.dumps(claims).encode())
    m = si.encode('ascii')
    if alg == 'RS256':
        n, _, d = state['rsa']
        k = (n.bit_length() + 7) // 8
        sig = pow(int.from_bytes(_rsa_em(k, m), 'big'), d, n).to_bytes(k, 'big')
    elif alg == 'ES256':
        d = state['ec'][0]
        z = int.from_bytes(hashlib.sha256(m).digest(), 'big')
        while True:
            kk = state['rng'].randrange(1, _N)
            r = _ec_mul(kk, _G)[0] % _N
            s = pow(kk, -1, _N) * (z + r * d) % _N
            if r and s:
                break
        sig = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
    else:
        sig = hmac.new(b'shared-secret', m, hashlib.sha256).digest()
    return si + '.' + b64u_enc(sig)


def _issue(state, client_id, account, nonce, with_id=True):
    state['n_tokens'] += 1
    n = state['n_tokens']
    at, rt = 'at-%d-%s' % (n, secrets.token_hex(6)), 'rt-%d-%s' % (n, secrets.token_hex(6))
    state['valid_access'].add(at)
    state['issued'].update([at, rt])
    state['refresh'][rt] = account
    body = {'access_token': at, 'refresh_token': rt, 'token_type': 'Bearer', 'expires_in': state.get('expires_in', 3600),
            'scope': state.get('scope', SCOPES), 'earliest_refresh_at': int(time.time()) + 60}
    if with_id:
        claims = {'iss': state['base'], 'aud': state.get('aud_override') or client_id, 'sub': account['sub'],
                  'email': account['email'], 'iat': int(time.time()), 'exp': int(time.time()) + 3600}
        if nonce is not None:
            claims['nonce'] = state.get('nonce_override') or nonce
        body['id_token'] = _sign_jwt(state, claims)
        state['issued'].add(body['id_token'])
    return body


def _plan_state():
    rng = random.Random(20261113)
    n, e, d = _test_rsa(rng)
    ec_d = rng.randrange(1, _N)
    ec_q = _ec_mul(ec_d, _G)
    jwks = [{'kty': 'RSA', 'kid': 'rsa1', 'alg': 'RS256', 'use': 'sig',
             'n': b64u_enc(n.to_bytes((n.bit_length() + 7) // 8, 'big')), 'e': b64u_enc(e.to_bytes(3, 'big'))},
            {'kty': 'EC', 'kid': 'ec1', 'alg': 'ES256', 'use': 'sig', 'crv': 'P-256',
             'x': b64u_enc(ec_q[0].to_bytes(32, 'big')), 'y': b64u_enc(ec_q[1].to_bytes(32, 'big'))}]
    return {'alg': 'RS256', 'rsa': (n, e, d), 'ec': (ec_d, ec_q), 'rng': rng, 'jwks': jwks, 'authorize': [],
            'codes': {}, 'token_requests': [], 'refresh': {}, 'valid_access': set(), 'issued': set(), 'revoked': [],
            'requests': [], 'script': [], 'n_clients': 0, 'n_tokens': 0, 'n_refresh': 0,
            'models': [{'slug': 'gpt-6.1-sol', 'display_name': 'GPT-6.1 Sol', 'visibility': 'list'},
                       {'slug': 'gpt-6-luna', 'display_name': 'GPT-6 Luna', 'visibility': 'list'}],
            'account': {'sub': 'user-abc', 'email': 'tester@example.edu'}}


def _mock_plan(state):
    """Local stand-in for auth.openai.com and api.openai.com on the ChatGPT plan route."""

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _json(self, code, obj):
            data = json.dumps(obj).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _bearer_ok(self):
            a = self.headers.get('Authorization', '')
            return a.startswith('Bearer ') and a[7:] in state['valid_access']

        def do_GET(self):
            u = urllib.parse.urlsplit(self.path)
            q = dict(urllib.parse.parse_qsl(u.query))
            base = state['base']
            if u.path == '/.well-known/openid-configuration':
                return self._json(200, {'issuer': base, 'jwks_uri': base + '/jwks',
                                        'revocation_endpoint': base + '/oauth/revoke'})
            if u.path == '/jwks':
                return self._json(200, {'keys': state['jwks']})
            if u.path == '/api/accounts/authorize':
                state['authorize'].append(q)
                back = {'state': q.get('state', '')}
                if state.get('deny'):
                    back['error'] = 'access_denied'
                else:
                    if q.get('client_id') == 'dynamic_agent_client':
                        state['n_clients'] += 1
                        cid = 'oaiapp_test%03d' % state['n_clients']
                        back['client_id'] = cid
                    else:
                        cid = q.get('client_id')
                        if state.get('callback_client_id'):
                            back['client_id'] = state['callback_client_id']
                    code = 'code-%d' % len(state['authorize'])
                    state['codes'][code] = {'q': q, 'client_id': cid, 'account': dict(state['account'])}
                    back['code'] = code
                self.send_response(302)
                self.send_header('Location', q.get('redirect_uri', '') + '?' + urllib.parse.urlencode(back))
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            if u.path == '/v1/models':
                if not self._bearer_ok():
                    return self._json(401, {'detail': 'invalid token'})
                return self._json(200, {'models': state['models']})
            self._json(404, {'detail': 'not found'})

        def do_POST(self):
            n = int(self.headers.get('Content-Length', 0))
            raw = self.rfile.read(n)
            u = urllib.parse.urlsplit(self.path)
            if u.path == '/api/accounts/oauth/token':
                f = dict(urllib.parse.parse_qsl(raw.decode('utf-8')))
                state['token_requests'].append(f)
                if f.get('grant_type') == 'authorization_code':
                    c = state['codes'].pop(f.get('code', ''), None)
                    ok = (c is not None and f.get('client_id') == c['client_id'] and
                          f.get('redirect_uri') == c['q'].get('redirect_uri') and f.get('resource') == RESOURCE and
                          b64u_enc(hashlib.sha256(f.get('code_verifier', '').encode()).digest()) ==
                          c['q'].get('code_challenge'))
                    if not ok:
                        return self._json(400, {'error': 'invalid_grant'})
                    return self._json(200, _issue(state, c['client_id'], c['account'], c['q'].get('nonce')))
                if f.get('grant_type') == 'refresh_token':
                    if state.get('refresh_error'):
                        return self._json(400, {'error': state['refresh_error']})
                    acct = state['refresh'].pop(f.get('refresh_token', ''), None)
                    if acct is None or f.get('resource') != RESOURCE or not f.get('client_id', '').startswith('oaiapp_'):
                        return self._json(400, {'error': 'invalid_grant'})
                    state['n_refresh'] += 1
                    return self._json(200, _issue(state, f.get('client_id'), acct, None, with_id=False))
                return self._json(400, {'error': 'unsupported_grant_type'})
            if u.path == '/oauth/revoke':
                state['revoked'].append(dict(urllib.parse.parse_qsl(raw.decode('utf-8'))))
                self.send_response(200)
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            if u.path == '/v1/responses':
                req = json.loads(raw.decode('utf-8'))
                state['requests'].append(req)
                if not self._bearer_ok():
                    return self._json(401, {'detail': 'access token expired'})
                act = state['script'].pop(0) if state['script'] else None
                if act == 'usage429':
                    return self._json(429, {'error': {'code': USAGE_LIMIT, 'message': 'limit'}})
                if act == 'not_eligible':
                    return self._json(403, {'error': {'code': 'subscription_sharing_user_not_eligible', 'message': 'no'}})
                if act == 'expire':
                    state['valid_access'].clear()
                    return self._json(401, {'detail': 'access token expired'})
                if 'reasoning' in req and state.get('reject_reasoning'):
                    return self._json(400, {'error': {'code': UNSUPPORTED, 'param': 'reasoning', 'message': 'no'}})
                bad = [k for k in ('max_output_tokens', 'temperature', 'top_p') if k in req]
                if bad or req.get('store') is not False or req.get('stream') is not True:
                    return self._json(400, {'error': {'code': UNSUPPORTED, 'param': (bad or ['stream'])[0]}})
                text = _mock_reply(req)
                eff = (req.get('reasoning') or {}).get('effort') or state.get('default_effort', 'medium')
                resp = {'id': 'resp_p%d' % len(state['requests']), 'object': 'response',
                        'model': 'gpt-6.1-sol-2026-09-29', 'status': 'completed', 'reasoning': {'effort': eff},
                        'output': [{'type': 'reasoning', 'summary': []},
                                   {'type': 'message', 'role': 'assistant',
                                    'content': [{'type': 'output_text', 'text': text}]}],
                        'usage': {'input_tokens': 1000, 'input_tokens_details': {'cached_tokens': 200},
                                  'output_tokens': 3000, 'output_tokens_details': {'reasoning_tokens': 2000}}}
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream')
                self.end_headers()

                def ev(obj):
                    self.wfile.write(('event: %s\ndata: %s\n\n' % (obj['type'], json.dumps(obj))).encode('utf-8'))
                    self.wfile.flush()
                ev({'type': 'response.created', 'response': {'id': resp['id'], 'status': 'in_progress'}})
                self.wfile.write(b': keep-alive\n\n')
                chunks = [text[i:i + 40] for i in range(0, len(text), 40)] or ['']
                if act == 'interrupt':
                    ev({'type': 'response.output_text.delta', 'delta': chunks[0], 'output_index': 1})
                    return
                if act == 'failed_usage':
                    ev({'type': 'response.failed', 'response': {'id': resp['id'], 'status': 'failed',
                                                                'error': {'code': USAGE_LIMIT, 'message': 'limit'}}})
                    return
                for c in chunks:
                    ev({'type': 'response.output_text.delta', 'delta': c, 'output_index': 1, 'content_index': 0})
                if act == 'deltas_only':
                    resp = dict(resp, output=[])
                ev({'type': 'response.completed', 'response': resp})
                return
            self._json(404, {'detail': 'not found'})

    srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
    state['base'] = 'http://127.0.0.1:%d' % srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def _browser_for(state):
    def go(url):
        def run():
            try:
                urllib.request.urlopen(url, timeout=20).read()
            except Exception as e:   # noqa: BLE001
                state['browser_error'] = str(e)
        threading.Thread(target=run, daemon=True).start()
        return True
    return go


def _small_plan(d, ids, name='plan.csv'):
    plan = os.path.join(d, name)
    src = list(csv.DictReader(open(os.path.join(HERE, 'run_plan.csv'), encoding='utf-8')))
    with open(plan, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(src[0].keys()))
        w.writeheader()
        w.writerows([r for r in src if r['run_id'] in ids])
    return plan


def _files_containing(root, needles):
    """Files under root (or the file root itself) that contain any of the needles."""
    hits = []
    needles = [x for x in needles if x]
    paths = [root] if os.path.isfile(root) else [os.path.join(r, fn) for r, _, fs in os.walk(root) for fn in fs]
    for p in paths:
        try:
            text = open(p, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        if any(x in text for x in needles):
            hits.append(p)
    return hits


def selftest():
    os.environ['RUN_LLM_FAST_RETRY'] = '1'
    fails = []
    saved_conf = dict(CONF)

    def check(cond, what):
        print(('ok   ' if cond else 'FAIL ') + what)
        if not cond:
            fails.append(what)

    def raises(fn, exc=Fatal):
        try:
            fn()
        except exc:
            return True
        except Exception:   # noqa: BLE001
            return False
        return False

    quiet = lambda m: None
    # transcription rule
    check(transcribe('PROGRAM Main\nEND_PROGRAM') == 'PROGRAM Main\nEND_PROGRAM', 'no fence: whole text')
    check(transcribe('x\n```iecst\nA\n```\ny') == 'A', 'one fence with language tag')
    check(transcribe('```\nA\n```\ntext\n```st\nB\n```') == 'A\n\nB', 'two fences joined by a blank line')
    check(transcribe('intro\n```json\n{"a": 1}') == '{"a": 1}', 'unclosed fence runs to the end')
    check(transcribe('~~~\nA\n~~~') == 'A', 'tilde fence')
    # rendering equals render_prompt.py
    with tempfile.TemporaryDirectory() as d:
        i0, g0 = os.path.join(d, 'i.md'), os.path.join(d, 'g.json')
        open(i0, 'w').write('IDEF0 table\n')
        open(g0, 'w').write('{"graphs": []}\n')
        same = True
        for t in ('T1', 'T2', 'T3', 'T4'):
            for tpl in ('A1_1_idef0', 'A1_2_grafcet', 'A1_3_st', 'A2_1_idef0', 'A2_2_grafcet', 'A2_3_st', 'B_st'):
                cmd = [sys.executable, os.path.join(HERE, 'render_prompt.py'), t, tpl, '--idef0', i0, '--grafcet', g0]
                ref = subprocess.run(cmd, capture_output=True, check=True, encoding='utf-8',
                                     env=dict(os.environ, PYTHONIOENCODING='utf-8')).stdout
                mine = render(tpl, t, read(i0), read(g0)) + '\n'
                same &= (ref == mine)
        check(same, 'prompts identical to render_prompt.py (4 tasks x 7 templates)')
    # ---- API-key route against a local mock of the Responses API
    state = {'requests': [], 'fail_next': 1}
    port = []
    srv = _mock(port, state)
    ep = 'http://127.0.0.1:%d/v1/responses' % port[0]
    with tempfile.TemporaryDirectory() as d:
        CONF['cred_dir'] = os.path.join(d, 'cred')
        plan = _small_plan(d, ('T2-W-01', 'T2-B-01'))
        base = os.path.join(d, 'out')
        s = run_plan(plan, base, 50.0, workers=2, endpoint=ep, log=quiet, key='sk-selftest-0000')
        check(s['done'] == 2 and s['calls'] == 7, 'API route: two rows, seven calls (6 workflow + 1 baseline)')
        check(len(state['requests']) == 8, 'API route: one 429 retried (eight requests)')
        reqs = state['requests']
        check(all('temperature' not in q and 'top_p' not in q and 'stream' not in q for q in reqs),
              'API route: temperature, top_p and stream never sent')
        check(all(q['model'] == 'gpt-6.1-sol' and q['reasoning'] == {'effort': 'medium'} and q['store'] is False
                  and q['max_output_tokens'] == 64000 for q in reqs), 'API route: registered settings in every request')
        roles = [[m['role'] for m in q['input']] for q in reqs]
        three = [q for q, r in zip(reqs, roles) if r == ['user', 'assistant', 'user', 'assistant', 'user']]
        check(len(three) == 2, 'third turn of each lane carries the two earlier turns (A1 and A2)')
        new = [q['input'][0]['content'].split('\n', 1)[0] for q, r in zip(reqs, roles) if r == ['user']]
        check(any(x.startswith('You are a PLC engineer') for x in new) and
              any(x.startswith('Act as an independent reviewer') for x in new) and
              any(x.startswith('Write IEC 61131-3') for x in new), 'A1, A2 and baseline each start a new conversation')
        a2 = [q for q in reqs if q['input'][0]['content'].startswith('Act as an independent reviewer')]
        check(all('Control the tank' not in json.dumps(q['input'][:1]) and
                  not any(m['content'].startswith('You are a PLC engineer') for m in q['input']) for q in a2),
              'A2 conversation contains no A1 turn')
        st = open(os.path.join(base, 'T2-W-01', 'a1_code.st'), encoding='utf-8').read()
        check(st.strip() == SAMPLE_ST, 'ST transcribed from fence')
        js = json.load(open(os.path.join(base, 'T2-W-01', 'a1_grafcet.json'), encoding='utf-8'))
        check('graphs' in js, 'GRAFCET JSON transcribed from fence and parses')
        led = [json.loads(x) for x in open(os.path.join(base, 'llm_ledger.jsonl'), encoding='utf-8')]
        exp = (800 * 2.5 + 200 * 0.1 + 3000 * 10.0) / 1e6
        check(len(led) == 7 and abs(led[0]['cost_usd'] - exp) < 1e-9 and led[0]['route'] == 'api' and
              led[0]['settings_sha256'] == settings_digest(settings_for('api')),
              'ledger: 7 records, cost per call US$%.6f, route and settings digest' % exp)
        rows = list(csv.DictReader(open(plan, encoding='utf-8')))
        check(all(r['model'] == 'gpt-6.1-sol' and r['temperature'] == TEMPERATURE_FIELD and r['run_date'] for r in rows),
              'run sheet filled: model, model_version, temperature, run_date')
        check(not _files_containing(d, ['sk-selftest-0000']), 'API key written to no file')
        rr = os.path.join(base, 'T2-W-01', 'raw')
        os.remove(os.path.join(rr, 'done.json'))
        for ext in ('.prompt.txt', '.response.json', '.output.txt'):
            os.remove(os.path.join(rr, 'A2_3_st' + ext))
        n0 = len(state['requests'])
        s2 = run_plan(plan, base, 50.0, workers=1, endpoint=ep, log=quiet, key='sk-selftest-0000')
        check(len(state['requests']) - n0 == 1 and s2['calls'] == 1, 'resume repeats only the missing call')
        check(len(state['requests'][-1]['input']) == 5, 'resumed call rebuilt the A2 conversation from saved turns')
        rb = os.path.join(base, 'T2-B-01', 'raw')
        os.remove(os.path.join(rb, 'done.json'))
        with open(os.path.join(rb, 'B_st.response.json'), 'w', encoding='utf-8') as f:
            f.write('{"id": "resp_cut')
        n0 = len(state['requests'])
        run_plan(plan, base, 50.0, workers=1, endpoint=ep, log=quiet, key='sk-selftest-0000')
        check(len(state['requests']) - n0 == 1 and json.load(open(os.path.join(rb, 'B_st.response.json'),
                                                                  encoding='utf-8')).get('status') == 'completed',
              'a call whose saved response was cut off is made again')
        s3 = run_plan(plan, os.path.join(d, 'out3'), 0.10, workers=1, endpoint=ep, log=quiet, key='sk-selftest-0000')
        check(s3['calls'] == 0 and (s3['stopped'] or '').startswith('budget'), 'budget guard stops before the first call')
        state['fatal'] = True
        check(raises(lambda: run_plan(plan, os.path.join(d, 'out4'), 50.0, workers=1, endpoint=ep, log=quiet,
                                      key='sk-selftest-0000')), 'HTTP 401 stops the run')
        state['fatal'] = False
        base5 = os.path.join(d, 'dry')
        s5 = run_plan(plan, base5, 0.0, workers=1, dry=True, log=quiet)
        check(s5['done'] == 2 and os.path.exists(os.path.join(base5, 'DRY_RUN')), 'dry run renders without calls')
        check(raises(lambda: run_plan(plan, base5, 50.0, workers=1, endpoint=ep, log=quiet, key='sk-selftest-0000')),
              'real run refused in a dry-run folder')
        prev_key = os.environ.get('OPENAI_API_KEY')
        os.environ['OPENAI_API_KEY'] = 'sk-selftest-0000'
        CONF['api_base'] = 'http://127.0.0.1:%d/v1' % port[0]
        try:
            pf = preflight('api', out=os.path.join(d, 'pre_api.json'), log=quiet, endpoint=ep)
            check(pf['ok'] and pf['model_listed'] and pf['reasoning_effort_reported'] == 'medium' and
                  not _files_containing(os.path.join(d, 'pre_api.json'), ['sk-selftest-0000']),
                  'API route preflight: model listed, one short call, key not in the record')
        finally:
            if prev_key is None:
                os.environ.pop('OPENAI_API_KEY', None)
            else:
                os.environ['OPENAI_API_KEY'] = prev_key
            CONF.update(saved_conf)
    # launcher: pilot, refused main (not frozen), frozen main, stop
    with tempfile.TemporaryDirectory() as kit:
        ex = os.path.join(kit, 'exec')
        os.makedirs(ex)
        shutil.copytree(os.path.join(HERE, 'prompts'), os.path.join(ex, 'prompts'))
        for f in ('freeze_prompts.py', 'run_llm.py'):
            shutil.copy2(os.path.join(HERE, f), os.path.join(ex, f))
        _small_plan(ex, ('T1-W-01', 'T3-B-02'), 'run_plan.csv')
        _small_plan(ex, ('T4-W-01', 'T4-B-01'), 'pilot_plan.csv')
        ctl = os.path.join(kit, 'control')
        res = {}
        th = threading.Thread(target=lambda: res.setdefault('spent', serve(kit, 5.0, 2, endpoint=ep, poll=0.1,
                                                                           key='sk-selftest-0000')), daemon=True)
        import contextlib
        import io
        with contextlib.redirect_stdout(io.StringIO()):
            th.start()

            def wait_for(st_name, tries=600):
                for _ in range(tries):
                    try:
                        if json.load(open(os.path.join(ctl, 'status.json'), encoding='utf-8'))['state'] == st_name \
                                and not os.path.exists(os.path.join(ctl, 'next.json')):
                            return True
                    except (OSError, ValueError, KeyError):
                        pass
                    time.sleep(0.05)
                return False
            ok1 = wait_for('waiting') and os.path.exists(os.path.join(kit, 'pilot_runs', 'PILOT_DONE'))
            json.dump({'action': 'main'}, open(os.path.join(ctl, 'next.json'), 'w'))
            time.sleep(0.5)
            ok2 = wait_for('waiting') and not os.path.exists(os.path.join(kit, 'runs'))
            subprocess.run([sys.executable, os.path.join(ex, 'freeze_prompts.py')], capture_output=True, check=True)
            json.dump({'action': 'main'}, open(os.path.join(ctl, 'next.json'), 'w'))
            time.sleep(0.5)
            ok3 = wait_for('waiting') and os.path.exists(os.path.join(kit, 'runs', 'T1-W-01', 'raw', 'done.json'))
            json.dump({'action': 'stop'}, open(os.path.join(ctl, 'next.json'), 'w'))
            th.join(10)
        check(ok1, 'launcher runs the pilot from a copy of the pilot plan, then waits')
        check(ok2, 'launcher refuses the main run while the prompts are not frozen')
        check(ok3, 'launcher runs the main plan after freezing')
        check(not th.is_alive() and res.get('spent', 0) > 0, 'launcher stops on the control file (spent US$%.3f)'
              % res.get('spent', 0))
        filled = list(csv.DictReader(open(os.path.join(ex, 'runs.csv'), encoding='utf-8')))
        check(all(r['model'] == 'gpt-6.1-sol' for r in filled), 'main run filled exec/runs.csv; run_plan.csv unchanged')
    if shutil.which('curl'):
        code, text, hdr = _curl_request('POST', ep, json.dumps({
            'model': 'm', 'input': [{'role': 'user', 'content': 'x'}], 'reasoning': {}, 'max_output_tokens': 1,
            'store': False}).encode(), {'Authorization': 'Bearer sk-selftest-0000', 'Content-Type': 'application/json'}, 30)
        check(code == 200 and json.loads(text)['status'] == 'completed', 'curl transport (key on standard input)')
    srv.shutdown()

    # ---- ID token checks
    ps = _plan_state()
    ps['base'] = 'https://issuer.test'
    good = {'iss': ps['base'], 'aud': 'oaiapp_x', 'sub': 's1', 'nonce': 'n1', 'exp': int(time.time()) + 600}
    jw = {'keys': ps['jwks']}
    tok = _sign_jwt(ps, good)
    check(validate_id_token(tok, jw, ps['base'], 'oaiapp_x', 'n1')['sub'] == 's1', 'ID token RS256 accepted')
    h, p_, s_ = tok.split('.')
    forged = h + '.' + b64u_enc(json.dumps(dict(good, sub='s2')).encode()) + '.' + s_
    check(raises(lambda: validate_id_token(forged, jw, ps['base'], 'oaiapp_x', 'n1')), 'ID token with changed claims refused')
    check(raises(lambda: validate_id_token(tok, jw, ps['base'], 'oaiapp_y', 'n1')), 'ID token for another client refused')
    check(raises(lambda: validate_id_token(tok, jw, ps['base'], 'oaiapp_x', 'n2')), 'ID token with another nonce refused')
    check(raises(lambda: validate_id_token(tok, jw, 'https://other.test', 'oaiapp_x', 'n1')), 'ID token of another issuer refused')
    old = _sign_jwt(ps, dict(good, exp=int(time.time()) - 3600))
    check(raises(lambda: validate_id_token(old, jw, ps['base'], 'oaiapp_x', 'n1')), 'expired ID token refused')
    ps['alg'] = 'ES256'
    t2 = _sign_jwt(ps, good)
    check(validate_id_token(t2, jw, ps['base'], 'oaiapp_x', 'n1')['sub'] == 's1', 'ID token ES256 accepted')
    h2, _, s2_ = t2.split('.')
    forged2 = h2 + '.' + b64u_enc(json.dumps(dict(good, sub='s2')).encode()) + '.' + s2_
    check(raises(lambda: validate_id_token(forged2, jw, ps['base'], 'oaiapp_x', 'n1')),
          'ES256 signature over other claims refused')
    ps['alg'] = 'HS256'
    check(raises(lambda: validate_id_token(_sign_jwt(ps, good), jw, ps['base'], 'oaiapp_x', 'n1')),
          'ID token with an unsupported algorithm refused')

    # ---- ChatGPT plan route against a local mock of auth.openai.com and api.openai.com
    st = _plan_state()
    psrv = _mock_plan(st)
    pb = st['base']
    with tempfile.TemporaryDirectory() as d:
        CONF.update({'auth_base': pb, 'api_base': pb + '/v1', 'cred_dir': os.path.join(d, 'cred'),
                     'open_browser': _browser_for(st), 'pause_s': 0.2, 'callback_ports': [0]})
        cfile = cred_path('chatgpt.json')
        info = signin(log=quiet, timeout_s=20)
        prof = load_json(cfile) or {}
        q0 = st['authorize'][0] if st['authorize'] else {}
        check(q0.get('client_id') == 'dynamic_agent_client' and q0.get('agent_name_hint') == AGENT_NAME and
              q0.get('ext_agent_host_id') == host_id() and q0.get('resource') == RESOURCE and
              PLAN_SCOPE in q0.get('scope', '').split() and 'offline_access' in q0.get('scope', '').split() and
              q0.get('code_challenge_method') == 'S256' and q0.get('response_type') == 'code' and
              q0.get('redirect_uri', '').startswith('http://127.0.0.1:') and
              q0.get('redirect_uri', '').endswith('/auth/callback') and q0.get('state') and q0.get('nonce'),
              'first sign-in: registration request as documented (dynamic client, host ID, PKCE S256, scopes, resource)')
        check(prof.get('client_id') == 'oaiapp_test001' and prof.get('access_token') and prof.get('refresh_token') and
              prof.get('subject') == 'user-abc' and info['account'] == 'te***@example.edu',
              'issued client ID, identity and tokens saved')
        if os.name == 'posix':
            check(oct(os.stat(cfile).st_mode & 0o777) == oct(0o600), 'credential file is owner-only (0600)')
        signin(log=quiet, timeout_s=20)
        q1 = st['authorize'][-1]
        check(q1.get('client_id') == 'oaiapp_test001' and 'agent_name_hint' not in q1 and q1.get('id_token_hint') and
              q1.get('login_hint') == 'tester@example.edu' and q1.get('ext_agent_host_id') == q0.get('ext_agent_host_id'),
              'returning sign-in reuses the client ID and host ID, sends the ID token hint')
        good_prof = open(cfile, encoding='utf-8').read()
        st['scope'] = 'openid profile email offline_access'
        check(raises(lambda: signin(log=quiet, timeout_s=20)) and open(cfile, encoding='utf-8').read() == good_prof,
              'sign-in without the plan scope refused; saved sign-in unchanged')
        del st['scope']
        st['account'] = {'sub': 'user-other', 'email': 'other@example.edu'}
        check(raises(lambda: signin(log=quiet, timeout_s=20)), 'sign-in with a different account refused')
        st['account'] = {'sub': 'user-abc', 'email': 'tester@example.edu'}
        st['deny'] = True
        check(raises(lambda: signin(log=quiet, timeout_s=20)), 'sign-in denied in the browser stops')
        st['deny'] = False
        st['callback_client_id'] = 'oaiapp_test999'
        check(raises(lambda: signin(log=quiet, timeout_s=20)), 'answer with another client registration refused')
        del st['callback_client_id']
        st['nonce_override'] = 'other'
        check(raises(lambda: signin(log=quiet, timeout_s=20)), 'ID token with another nonce refused at sign-in')
        del st['nonce_override']
        st['alg'] = 'ES256'
        signin(log=quiet, timeout_s=20)
        check('access_token' in (load_json(cfile) or {}), 'sign-in with an ES256 ID token')
        st['alg'] = 'RS256'
        # preflight
        pre = os.path.join(d, 'pre.json')
        pf = preflight('chatgpt', out=pre, log=quiet)
        check(pf['ok'] and pf['model_listed'] and pf['reasoning_effort_reported'] == 'medium' and
              not pf['omit_reasoning'] and pf['reply'] == 'OK' and os.path.exists(pre),
              'ChatGPT preflight: model listed, one short streamed call, effort medium')
        st['reject_reasoning'] = True
        pf2 = preflight('chatgpt', log=quiet)
        check(pf2['ok'] and pf2['omit_reasoning'] and pf2['reasoning_effort_reported'] == 'medium',
              'preflight: reasoning field refused, sent again without it, reported effort medium')
        st['default_effort'] = 'low'
        check(raises(lambda: preflight('chatgpt', log=quiet)), 'preflight stops when the route default effort is not medium')
        st['reject_reasoning'] = False
        st['default_effort'] = 'medium'
        st['models'] = [{'slug': 'gpt-6-luna', 'visibility': 'list'}, {'slug': 'gpt-6.1-sol', 'visibility': 'hidden'}]
        check(raises(lambda: preflight('chatgpt', log=quiet)), 'preflight stops when gpt-6.1-sol is not listed')
        st['models'] = _plan_state()['models']
        st['script'] = ['usage429']
        check(raises(lambda: preflight('chatgpt', log=quiet)), 'preflight reports the usage limit instead of pausing')
        st['script'] = []
        # run on the plan route
        plan = _small_plan(d, ('T2-W-01', 'T2-B-01'))
        base = os.path.join(d, 'plan_out')
        n0 = len(st['requests'])
        st['script'] = ['usage429', 'failed_usage', 'interrupt', 'expire']
        rt_before = (load_json(cfile) or {}).get('refresh_token')
        s = run_plan(plan, base, 0.0, workers=1, log=quiet, route='chatgpt')
        reqs = st['requests'][n0:]
        check(s['done'] == 2 and s['calls'] == 7 and s['route'] == 'chatgpt', 'ChatGPT route: two rows, seven calls')
        check(len(reqs) == 11, 'usage limit (HTTP 429 and response.failed), interrupted stream and expired token '
                               'handled (eleven requests)')
        check(all(q.get('stream') is True and q.get('store') is False and q.get('model') == 'gpt-6.1-sol' and
                  q.get('reasoning') == {'effort': 'medium'} and
                  not any(k in q for k in ('max_output_tokens', 'temperature', 'top_p')) for q in reqs),
              'ChatGPT route: stream and store as required, reasoning medium, no output limit, no temperature or top_p')
        pauses = [json.loads(x) for x in open(os.path.join(base, 'pauses.jsonl'), encoding='utf-8')]
        check(len(pauses) == 2 and s['pauses'] == 2, 'two usage-limit pauses recorded, not counted as retries')
        led = [json.loads(x) for x in open(os.path.join(base, 'llm_ledger.jsonl'), encoding='utf-8')]
        check(len(led) == 7 and led[0]['attempts'] == 2 and sum(r['attempts'] for r in led) == 8,
              'interrupted stream counted as one retry (attempts 2), the other calls first time')
        check(all(r['cost_usd'] == 0.0 and r['cost_usd_api_equivalent'] > 0 and r['route'] == 'chatgpt' and
                  r['reasoning_effort_reported'] == 'medium' and
                  r['settings_sha256'] == settings_digest(settings_for('chatgpt')) for r in led),
              'ledger: no charge on the plan, API-equivalent cost, route, reported effort, settings digest')
        check(settings_digest(settings_for('chatgpt')) != settings_digest(settings_for('api')),
              'the two routes have different settings digests')
        st_text = open(os.path.join(base, 'T2-W-01', 'a1_code.st'), encoding='utf-8').read()
        check(st_text.strip() == SAMPLE_ST, 'ST transcribed from the streamed response')
        rt_after = (load_json(cfile) or {}).get('refresh_token')
        check(st['n_refresh'] >= 1 and rt_after and rt_after != rt_before, 'expired access token refreshed; rotated '
                                                                           'refresh token saved')
        check(not _files_containing(base, st['issued']) and not _files_containing(pre, st['issued']),
              'no token written into the run folder or the preflight record')
        # deltas only
        st['script'] = ['deltas_only']
        cl = PlanClient(PlanAuth(quiet), gate=PauseGate(0.1, quiet))
        data, _ = cl.respond(cl.payload([], 'Reply with the single word OK.'), quiet)
        check(output_text(data) == 'OK' and data['x_runner']['text_source'] == 'deltas',
              'text taken from the deltas when response.completed carries none')
        # refresh before expiry
        p = load_json(cfile)
        p['expires_at'] = time.time() + 10
        write_private(cfile, json.dumps(p))
        n_r = st['n_refresh']
        PlanAuth(quiet).token()
        check(st['n_refresh'] == n_r + 1, 'access token refreshed shortly before it expires')
        # terminal refresh error
        p = load_json(cfile)
        p['expires_at'] = 0
        write_private(cfile, json.dumps(p))
        st['refresh_error'] = 'refresh_token_reused'
        check(raises(lambda: PlanAuth(quiet).token()), 'terminal refresh error stops the run')
        p = load_json(cfile) or {}
        check('access_token' not in p and 'refresh_token' not in p and p.get('client_id') == 'oaiapp_test001',
              'unusable tokens cleared; client registration kept for the next sign-in')
        del st['refresh_error']
        signin(log=quiet, timeout_s=20)
        # not eligible
        st['script'] = ['not_eligible']
        n1 = len(st['requests'])
        check(raises(lambda: run_plan(plan, os.path.join(d, 'plan_ne'), 0.0, workers=1, log=quiet, route='chatgpt')),
              'not eligible (HTTP 403) stops the run')
        check(len(st['requests']) - n1 == 1, 'not eligible is not retried')
        # curl transport for the plan route
        if shutil.which('curl'):
            _MODE['transport'] = 'curl'
            try:
                signin(log=quiet, timeout_s=20)
                pfc = preflight('chatgpt', log=quiet)
                check(pfc['ok'] and pfc['reply'] == 'OK', 'curl transport: sign-in and streamed call')
            finally:
                _MODE['transport'] = 'urllib'
        # sign-out
        p = load_json(cfile)
        check(signout(log=quiet) and st['revoked'] and st['revoked'][-1].get('token_type_hint') == 'refresh_token' and
              st['revoked'][-1].get('token') == p['refresh_token'] and st['revoked'][-1].get('client_id') == p['client_id'],
              'sign-out revokes the refresh token')
        p2 = load_json(cfile) or {}
        check('access_token' not in p2 and p2.get('client_id') == p['client_id'] and
              os.path.exists(cred_path('host.json')), 'sign-out clears the tokens, keeps the registration and host ID')
        signout(log=quiet, forget=True)
        check(not os.path.exists(cfile) and os.path.exists(cred_path('host.json')), 'sign-out --forget drops the '
                                                                                    'registration')
        check(raises(lambda: PlanAuth(quiet)), 'a run without sign-in stops with a clear message')
    psrv.shutdown()
    CONF.update(saved_conf)
    print('selftest: %s' % ('passed' if not fails else 'FAILED (%d)' % len(fails)))
    return 0 if not fails else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('plan', nargs='?')
    ap.add_argument('--base')
    ap.add_argument('--budget', type=float, default=10.0, help='US$ limit for this run on the API route (default 10)')
    ap.add_argument('--workers', type=int, help='parallel rows (default 4 on the API route, 2 on the ChatGPT route)')
    ap.add_argument('--route', choices=['api', 'chatgpt'], default='api')
    ap.add_argument('--omit-reasoning', action='store_true',
                    help='ChatGPT route only, when the preflight found the reasoning field refused')
    ap.add_argument('--pilot', action='store_true', help='trial rows: prompts need not be frozen')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--only', help='comma-separated run_ids')
    ap.add_argument('--serve', metavar='KIT', help='launcher mode: pilot, then follow KIT/control/next.json')
    ap.add_argument('--cap', type=float, default=160.0, help='US$ limit of the whole serve session')
    ap.add_argument('--endpoint', help='for tests against a local server only')
    ap.add_argument('--signin', action='store_true')
    ap.add_argument('--signout', action='store_true')
    ap.add_argument('--forget', action='store_true', help='with --signout: also drop the client registration')
    ap.add_argument('--whoami', action='store_true')
    ap.add_argument('--where', action='store_true', help='print the credential folder')
    ap.add_argument('--preflight', metavar='OUT_JSON')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    workers = a.workers or (2 if a.route == 'chatgpt' else 4)
    try:
        if a.where:
            print(cred_dir())
            return
        if a.whoami:
            print(whoami())
            return
        if a.signin:
            info = signin()
            print('signed in with ChatGPT as %s; plan usage granted' % info['account'])
            return
        if a.signout:
            signout(forget=a.forget)
            print(whoami())
            return
        if a.preflight:
            r = preflight(a.route, a.preflight, omit_reasoning=a.omit_reasoning, endpoint=a.endpoint)
            print('preflight ok: %s' % json.dumps({k: r.get(k) for k in ('route', 'model_returned',
                                                                          'reasoning_effort_reported', 'omit_reasoning',
                                                                          'reply')}))
            return
        if a.serve:
            serve(os.path.abspath(a.serve), a.cap, workers, endpoint=a.endpoint, route=a.route,
                  omit_reasoning=a.omit_reasoning)
            return
        if not a.plan or not a.base:
            ap.error('plan and --base are required')
        if os.path.basename(a.plan) == 'run_plan.csv' and not a.dry_run:
            ap.error('copy run_plan.csv to runs.csv and run that copy; the registered plan stays unchanged')
        if not a.pilot and not a.dry_run:
            ok, msg = frozen_ok()
            if not ok:
                sys.exit('prompts are not frozen or changed since freezing: %s' % msg)
        run_plan(a.plan, a.base, a.budget, workers, dry=a.dry_run, endpoint=a.endpoint,
                 only=set(a.only.split(',')) if a.only else None, route=a.route, omit_reasoning=a.omit_reasoning)
    except Fatal as e:
        sys.exit('stopped: %s' % e)


if __name__ == '__main__':
    main()
