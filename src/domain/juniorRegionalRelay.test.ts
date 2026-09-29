// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'
import { relayJuniorRequest } from '../../supabase/functions/chemistry-access/junior-regional-relay'

const project = 'https://phdleezffrqqzyveicrm.supabase.co'
const endpoint = `${project}/functions/v1/chemistry-access`
const actions = ['junior_open_session', 'junior_submit_step', 'preview_junior_open_session', 'preview_junior_submit_step']
const rawBody = '{ "action": "junior_submit_step", "data": { "stepId":"immutable-step", "revisionToken":"v1", "selectedOption":2, "uncertain":false, "durationSec":11, "note":"化学\\n原样" } }\n'

function request(url = endpoint, extraHeaders: Record<string, string> = {}) {
  return new Request(url, { method: 'POST', body: rawBody, headers: {
    'content-type': 'application/json', apikey: 'sb_publishable_test', 'x-app-session': 'student-session',
    origin: 'https://ganlu6633-source.github.io', accept: 'application/json', ...extraHeaders,
  } })
}

function setup(response = new Response('{"payload":{}}', { status: 200 })) {
  const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(response)
  return { fetchMock, config: { supabaseUrl: project, currentRegion: 'ap-northeast-1', fetch: fetchMock } }
}

describe('single-hop junior regional transport', () => {
  it.each(actions)('relays %s once to the fixed same-project Sydney endpoint', async (action) => {
    const incoming = request(`${endpoint}/untrusted-path?redirect=https://attacker.example&forceFunctionRegion=ap-southeast-2`)
    const response = new Response('streamed response', { headers: { 'server-timing': 'total;dur=42' } })
    const { config, fetchMock } = setup(response)
    expect(await relayJuniorRequest(incoming, action, config)).toBe(response)
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url, init] = fetchMock.mock.calls[0]
    expect(String(url)).toBe(`${endpoint}?forceFunctionRegion=ap-southeast-2&chemRegionRelay=1`)
    expect(init?.method).toBe('POST')
    expect(init?.redirect).toBe('error')
    const headers = new Headers(init?.headers)
    expect(headers.get('x-chem-region-relay')).toBe('1')
    expect(headers.get('x-app-session')).toBe('student-session')
    expect(headers.get('apikey')).toBe('sb_publishable_test')
    expect(headers.get('origin')).toBe('https://ganlu6633-source.github.io')
    expect(response.bodyUsed).toBe(false)
    expect(await incoming.text()).toBe(rawBody)
    expect(new TextDecoder().decode(init?.body as ArrayBuffer)).toBe(rawBody)
  })

  it('preserves the original consumed JSON verbatim instead of reconstructing an answer', async () => {
    const incoming = request()
    const raw = await incoming.text()
    const { config, fetchMock } = setup()
    await relayJuniorRequest(incoming, JSON.parse(raw).action, { ...config, rawBody: raw })
    expect(fetchMock.mock.calls[0][1]?.body).toBe(rawBody)
  })

  it.each(['student_dashboard', 'start_plan', 'login', 'knowledge_skill_tree', undefined, null, {}])('never relays another action: %s', async (action) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(request(), action, config)).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each(['GET', 'OPTIONS', 'DELETE'])('does not relay %s', async (method) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(new Request(endpoint, { method, headers: { 'x-app-session': 'present' } }), actions[0], config)).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each(['', 'unknown', 'local', undefined, 'moon-1', 'ap-southeast-2'])('does not relay from an unknown/local/target region: %s', async (currentRegion) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(request(), actions[0], { ...config, currentRegion })).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each(['', '   '])('requires a nonblank app session, without treating its presence as verified identity', async (token) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(request(endpoint, { 'x-app-session': token }), actions[0], config)).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each([
    '?chemRegionalFallback=1', '?chemRegionRelay=1', '?forceFunctionRegion=any',
    '?forceFunctionRegion=us-east-1', '?forceFunctionRegion=',
    '?forceFunctionRegion=ap-southeast-2&forceFunctionRegion=any',
  ])('honors an explicit fallback/region/hop query: %s', async (query) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(request(endpoint + query), actions[0], config)).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each(['1', '0', ''])('treats any relay-header presence as a hard one-hop guard: %s', async (value) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(request(endpoint, { 'X-Chem-Region-Relay': value }), actions[0], config)).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each([
    'https://attacker.example', 'http://phdleezffrqqzyveicrm.supabase.co',
    'https://phdleezffrqqzyveicrm.supabase.co.attacker.example',
    `${project}/other`, `${project}?target=attacker`, `${project}:8443`,
    'https://secret@phdleezffrqqzyveicrm.supabase.co', 'not a URL',
  ])('never sends the incoming token to an invalid deployment destination: %s', async (supabaseUrl) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(request(), actions[0], { ...config, supabaseUrl })).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each([
    'http://edge-runtime:9000/chemistry-access?target=https://attacker.example',
    'http://localhost:8000/functions/v1/chemistry-access',
    'https://attacker.example/functions/v1/another-function',
    'https://aaaaaaaaaaaaaaaaaaaa.supabase.co/functions/v1/chemistry-access',
  ])('uses only the trusted deployment destination despite a rewritten request URL: %s', async (incomingUrl) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(request(incomingUrl), actions[0], config)).toBeInstanceOf(Response)
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(String(fetchMock.mock.calls[0][0])).toBe(`${endpoint}?forceFunctionRegion=ap-southeast-2&chemRegionRelay=1`)
  })

  it('still observes fallback and hop guards after the ingress origin is rewritten', async () => {
    const { config, fetchMock } = setup()
    for (const guard of ['chemRegionRelay=1', 'chemRegionalFallback=1', 'forceFunctionRegion=any']) {
      expect(await relayJuniorRequest(request(`http://edge-runtime:9000/chemistry-access?${guard}`), actions[1], config)).toBeNull()
    }
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('forwards no authorization, cookie, forwarded identity, or unrelated headers', async () => {
    const { config, fetchMock } = setup()
    await relayJuniorRequest(request(endpoint, {
      authorization: 'Bearer secret-service-role', cookie: 'private=value', 'x-forwarded-for': '127.0.0.1',
      'x-region': 'us-east-1', 'x-user-id': 'teacher', 'x-client-info': 'test-client',
    }), actions[0], config)
    const headers = new Headers(fetchMock.mock.calls[0][1]?.headers)
    expect([...headers.keys()].sort()).toEqual(['accept', 'apikey', 'content-type', 'origin', 'x-app-session', 'x-chem-region-relay', 'x-client-info'])
  })

  it.each(['sb_secret_test', `header.${btoa(JSON.stringify({ role: 'service_role' }))}.signature`])('does not relay a privileged API key', async (apikey) => {
    const { config, fetchMock } = setup()
    expect(await relayJuniorRequest(request(endpoint, { apikey }), actions[0], config)).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each([400, 401, 403, 409, 429])('returns target %s unchanged, without granting access or locally retrying', async (status) => {
    const response = new Response('target validation rejected this request', { status })
    const { config, fetchMock } = setup(response)
    expect(await relayJuniorRequest(request(endpoint, { 'x-app-session': 'unverified-token' }), actions[0], config)).toBe(response)
    expect(response.bodyUsed).toBe(false)
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it.each([500, 502, 503, 504])('returns null after target %s for the original local gates, with no second fetch', async (status) => {
    const { config, fetchMock } = setup(new Response('regional failure', { status }))
    expect(await relayJuniorRequest(request(), actions[1], config)).toBeNull()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('returns null on a network failure without retrying or consuming the original body', async () => {
    const incoming = request()
    const { config, fetchMock } = setup()
    fetchMock.mockRejectedValueOnce(new TypeError('network unavailable'))
    expect(await relayJuniorRequest(incoming, actions[1], config)).toBeNull()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(await incoming.text()).toBe(rawBody)
  })

  it('never starts another regional fetch when the first response is routed back to the original region', async () => {
    const { config, fetchMock } = setup()
    await relayJuniorRequest(request(), actions[1], config)
    const [url, init] = fetchMock.mock.calls[0]
    const relayed = new Request(url, init)
    expect(await relayJuniorRequest(relayed, actions[1], config)).toBeNull()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('propagates cancellation instead of starting local processing after a cancelled relay', async () => {
    const controller = new AbortController()
    const incoming = new Request(request(), { signal: controller.signal })
    const { config, fetchMock } = setup()
    fetchMock.mockImplementationOnce(async () => { controller.abort(); throw new DOMException('cancelled', 'AbortError') })
    await expect(relayJuniorRequest(incoming, actions[1], config)).rejects.toMatchObject({ name: 'AbortError' })
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })
})
