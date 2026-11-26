import vm from 'node:vm';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
const live = process.argv.includes('--live');
const liveChecks = [];
let liveRequests = 0;
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../Sources/TVCore/ScriptAssets');
const storage = new Map();
const logs = [];
const context = vm.createContext({ console, URL, TextEncoder, TextDecoder });
context.__host = (op, argument) => {
  if (op === 'encode') return Buffer.from(argument).toString('base64');
  if (op === 'decode') return Buffer.from(JSON.parse(argument).base64, 'base64').toString('utf8');
  if (op === 'url') {
    const a = JSON.parse(argument), url = new URL(a.href, a.base || undefined);
    return JSON.stringify(Object.fromEntries(['href','origin','protocol','host','hostname','port','pathname','search','hash','username','password'].map(k => [k, url[k]])));
  }
  if (op === 'module') return fs.readFileSync(path.join(root, argument.replace('assets://', '')), 'utf8');
  if (op === 'md5') return crypto.createHash('md5').update(argument).digest('hex');
  if (op === 'novel.flag') return '';
  if (op === 'novel.log' || op === 'log') { logs.push(argument); if (process.env.DEBUG) console.error(argument); return null; }
  if (op === 'novel.store') {
    const a = JSON.parse(argument), key = a.source + ':' + a.key;
    if (a.op === 'get') return storage.get(key) ?? '';
    if (a.op === 'set') storage.set(key, a.value); else storage.delete(key);
    return null;
  }
  if (op === 'novel.decode') return Buffer.from(JSON.parse(argument).base64, 'base64').toString('utf8');
  if (op === 'novel.encode') return Buffer.from(JSON.parse(argument).text).toString('base64');
  if (op === 'novel.http') {
    const a = JSON.parse(argument);
    const u = new URL(a.url);
    if (live) return liveHTTP(u, a);
    requests.push({ path: u.pathname, method: a.method, body: a.body, query: Object.fromEntries(u.searchParams), headers: a.headers });
    const data = fixture(u, a);
    return JSON.stringify({ url: a.url, code: 200, headers: {}, cookies: {}, base64: Buffer.from(typeof data === 'string' ? data : JSON.stringify(data)).toString('base64') });
  }
  throw Error('Unexpected native operation: ' + op);
};
const modules = new Map();
async function load(identifier) {
  if (modules.has(identifier)) return modules.get(identifier);
  const file = path.join(root, identifier.replace('assets://', ''));
  const module = new vm.SourceTextModule(fs.readFileSync(file, 'utf8'), { context, identifier });
  modules.set(identifier, module);
  await module.link(specifier => load(specifier));
  return module;
}
await (await load('assets://tvbox/prelude.js')).evaluate();
await (await load('assets://legado/engine.js')).evaluate();
const engine = context.__legado;
function unwrap(answer) { assert.equal(answer.error, undefined, answer.error); return JSON.parse(JSON.stringify(answer.value)); }

const input = process.argv[2];
assert.ok(input, 'Usage: node --experimental-vm-modules scripts/test-guangyu.mjs <external-source.json>');
const parsed = JSON.parse(fs.readFileSync(input, 'utf8').replace(/^\uFEFF/, ''));
const source = Array.isArray(parsed) ? parsed.find(s => String(s.bookSourceName).includes('光遇')) : parsed;
assert.ok(source?.jsLib, 'Expected the external Guangyu source');
const requests = [];
let loginOK = false;
const record = {book_id: 'fixture-book', book_name: '文字测试', author: '测试作者', source: '测试平台', tab: '小说', abstract: '离线简介', thumb_url: '', word_number: '1000', title: '第一章', item_id: 'fixture-chapter'};
const unexpected = [];
function fixture(u, a) {
    if (u.pathname === '/login_api') {
        assert.equal(a.method, 'POST');
        assert.deepEqual(JSON.parse(a.body), {register_email: 'fixture@example.invalid', password: 'fixture-password'});
        return loginOK ? {code: 0, key: 'fixture-session-token'} : {code: 1, msg: '密码错误'};
    }
    if (u.pathname === '/search') return {data: [record]};
    if (u.pathname === '/detail') return {data: record};
    if (u.pathname === '/catalog') return {data: [record]};
    if (u.pathname === '/content') return {content: '<p>第一段文字。</p><p>第二段文字。</p>'};
    if (u.pathname === '/get_avatar') return {code: 1, msg: '请先登录'};
    if (u.pathname === '/static/source_config/config.json') return {version: 1, hosts: ['https://fixture.invalid'], 小说: ['测试平台']};
    if (u.pathname === '/discovestyle') return {data: [{title: '测试小说', url: 'https://fixture.invalid/discover?tab=小说&page={{page}}'}]};
    if (u.pathname === '/discover') return {data: [record]};
    unexpected.push(u.pathname);
    throw Error('Unlisted fixture endpoint: ' + u.pathname);
}

// --live permits only the three public GET endpoints. Ignore source-supplied headers/body,
// never follow redirects, never use a cookie jar, and retain only status/count metadata.
function liveHTTP(u, request) {
    const labels = {'/static/source_config/config.json': 'cloudConfig', '/discovestyle': 'discover', '/search': 'search'};
    const label = labels[u.pathname];
    if (!label || request.method !== 'GET' || u.protocol !== 'https:' || u.username || u.password || ++liveRequests > 12)
        throw Error('Live request outside read-only allowlist');
    let bytes, code = 0, data = null, status = 'network_error';
    try {
        const output = execFileSync(process.platform === 'win32' ? 'curl.exe' : 'curl', [
            '-q', '--silent', '--show-error', '--connect-timeout', '8', '--max-time', '15',
            '--max-filesize', '4194304', '--proto', '=https', '-H', 'Accept: application/json',
            '--write-out', '\n__STATUS__%{http_code}', u.href
        ], {maxBuffer: 5 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe']});
        const at = output.lastIndexOf('\n__STATUS__');
        code = Number(output.subarray(at + 11).toString()); bytes = output.subarray(0, at);
        data = JSON.parse(bytes.toString()); status = code === 200 ? 'json_received' : 'http_error';
    } catch { bytes = Buffer.from('{}'); }
    const check = {endpoint: label, status, httpStatus: code, count: Array.isArray(data?.data) ? data.data.length : 0};
    if (label === 'cloudConfig') for (const [key, field] of [['hosts', 'hosts'], ['小说', 'sources']]) {
        check[field + 'Count'] = Array.isArray(data?.[key]) ? data[key].length : 0;
        check[field + 'Status'] = Array.isArray(data?.[key]) && data[key].every(x => typeof x === 'string') ? 'string_array' : 'unverified';
    }
    if (typeof data?.code === 'number') check.apiCode = data.code;
    liveChecks.push(check);
    return JSON.stringify({url: u.href, code, headers: {}, cookies: {}, base64: bytes.toString('base64')});
}
function liveReport() {
    const loaded = engine.load(JSON.stringify(source));
    const first = engine.loginForm();
    const form = first.value;
    const options = name => form?.rows.find(r => r.name === name)?.chars || [];
    const discovered = engine.exploreKinds();
    const searched = engine.search('测试', 1, 45000);
    const report = {
        status: liveChecks.length >= 3 && liveChecks.every(c => c.status === 'json_received') ? 'responses_received' : 'incomplete',
        sourceLoadStatus: loaded.error ? 'failed' : 'passed',
        firstFormStatus: first.error ? 'failed' : 'passed',
        nativeSourceCount: options('搜索来源（文字阅读）').length,
        nativeHostCount: options('线路（文字阅读）').length,
        networkModeStatus: JSON.stringify(options('网络模式（文字阅读）')) === JSON.stringify(['服务器', '本地']) ? 'matches_original' : 'mismatch',
        discoverStatus: discovered.error ? 'failed' : 'completed', discoverCount: discovered.value?.length || 0,
        searchStatus: searched.error ? 'failed' : 'completed', searchCount: searched.value?.length || 0,
        authenticationWrites: 0, iOSRuntimeStatus: 'not_run', checks: liveChecks
    };
    fs.writeFileSync(new URL('../Docs/guangyu-live.json', import.meta.url), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
}
if (live) { liveReport(); process.exit(0); }

// The source is loaded verbatim; only HTTP responses are fixtures. No network tool is used.
unwrap(engine.load(JSON.stringify(source)));
const initial = unwrap(engine.loginForm());
assert.deepEqual(initial.rows.find(r => r.name === '搜索来源（文字阅读）').chars, ['全部', '测试平台']);
assert.equal(initial.values['网络模式（文字阅读）'], '服务器');
assert.deepEqual(initial.rows.find(r => r.name === '网络模式（文字阅读）').chars, ['服务器', '本地']);
assert.deepEqual(requests.map(r => r.path), ['/static/source_config/config.json']);
unwrap(engine.loginForm());
assert.equal(requests.length, 1, 'Repeated forms reuse the cloud configuration');
const found = unwrap(engine.search('测试', 1));
assert.equal(found.length, 1);
assert.equal(found[0].name, '文字测试');
assert.equal(found[0].author, '测试作者');
assert.match(found[0].url, /^data:;base64,.*"gydetail"/);
const book = unwrap(engine.info(found[0]));
assert.match(book.intro, /当前服务/); // Detect swallowed intro rule failures.
assert.match(book.tocURL, /"gycatalog"/);
const toc = unwrap(engine.toc(book));
assert.equal(toc.chapters.length, 1);
assert.match(toc.chapters[0].url, /"gycontent"/);
assert.equal(toc.book.variables.book_id, 'fixture-book');
const content = unwrap(engine.content(toc.book, toc.chapters[0], null));
assert.equal(content.title, '第一章');
assert.deepEqual(content.paragraphs, ['第一段文字。', '第二段文字。']);
const kinds = unwrap(engine.exploreKinds());
const category = kinds.find(k => k.title === '测试小说');
assert.ok(category);
assert.ok(kinds.every(k => k.url && !k.url.includes('startBrowser')));
assert.ok(category.url.includes('{{page}}'));
assert.equal(unwrap(engine.explore(category.url))[0].name, '文字测试');
const form = unwrap(engine.loginForm());
assert.ok(form.rows[0].wide);
assert.ok(!form.rows.some(r => /getServerSettings|getHtmlSettings|ste\('听书'/.test(r.action || '')));
assert.equal(form.rows.find(r => r.name === '密码').type, 'password');
assert.equal(form.rows.find(r => r.name === '邮箱').type, 'text');
assert.equal(form.rows.find(r => r.name === '线路（文字阅读）').type, 'select');
const values = {...form.values, '线路（文字阅读）': 'https://fixture.invalid', '频道（文字阅读）': '女频'};
unwrap(engine.loginAction(values, '__yingxia_apply_text_settings__'));
const before = requests.length;
unwrap(engine.exploreKinds());
assert.ok(requests.slice(before).some(r => r.path === '/discovestyle' && r.query.source_type === '女频'));
unwrap(engine.search('更新设置', 2));
assert.equal(requests.at(-1).query.page, '2');
const credentials = {'邮箱': 'fixture@example.invalid', '密码': 'fixture-password'};
const rejected = unwrap(engine.loginAction(credentials, 'login(true)'));
assert.equal(rejected.success, false);
assert.equal(unwrap(engine.loginForm()).signedIn, false);
assert.ok(rejected.said.some(s => s.includes('密码错误')));
const rejectedSubmit = unwrap(engine.login(credentials));
assert.equal(rejectedSubmit.success, false);
assert.equal(unwrap(engine.loginForm()).signedIn, false);
loginOK = true;
const accepted = unwrap(engine.loginAction({...values, ...credentials}, 'login(true)'));
assert.equal(accepted.success, true);
assert.equal(unwrap(engine.loginForm()).values['邮箱'], credentials['邮箱']);
assert.deepEqual(JSON.parse(storage.get(source.bookSourceUrl + ':login:info')), credentials);
assert.equal(unwrap(engine.loginForm()).signedIn, true);
assert.equal(unwrap(engine.loginCookies('https://fixture.invalid/login')), 'qttoken=fixture-session-token');
unwrap(engine.search('认证后', 1));
assert.match(requests.at(-1).headers.cookie, /qttoken=fixture-session-token/);
unwrap(engine.logout());
assert.equal(unwrap(engine.loginForm()).signedIn, false);
unwrap(engine.search('退出后', 1));
assert.doesNotMatch(requests.at(-1).headers.cookie, /fixture-session-token/);
assert.equal(unwrap(engine.loginAction({}, 'java.openUrl("https://example.invalid/login")')).open, 'https://example.invalid/login');
for (const action of ['getServerSettings()', 'getHtmlSettings()', 'getSvgSettings()']) {
    assert.match(engine.loginAction({}, action).error, /不支持/);
}
for (const tab of ['听书', '漫画', '短剧']) {
    assert.match(engine.loginAction({}, `ste('${tab}')`).error, /仅支持文字/);
    const envelope = 'data:;base64,' + Buffer.from(JSON.stringify({tab})).toString('base64') + ',{"type":"gydetail"}';
    assert.match(engine.info({url: envelope}).error, /仅支持文字/);
}
assert.equal(unwrap(engine.loginAction({}, 'java.startBrowser("https://example.invalid/login")')).open, 'https://example.invalid/login');
assert.equal(unwrap(engine.loginAction({}, 'java.startBrowserAwait("https://example.invalid/login")')).open, 'https://example.invalid/login');
assert.equal(unwrap(engine.loginCookies('https://fixture.invalid/login')), '');
unwrap(engine.keepCookies('https://fixture.invalid/login', 'qttoken=web-fixture-session'));
assert.equal(unwrap(engine.loginCookies('https://fixture.invalid/login')), 'qttoken=web-fixture-session');
unwrap(engine.keepCookies('https://fixture.invalid/login', 'other=value'));
assert.equal(unwrap(engine.loginCookies('https://fixture.invalid/login')), 'other=value');
unwrap(engine.keepCookies('https://fixture.invalid/login', ''));
assert.equal(unwrap(engine.loginCookies('https://fixture.invalid/login')), '');
assert.equal(unwrap(engine.loginForm()).signedIn, false);
unwrap(engine.logout());
assert.equal(unwrap(engine.loginCookies('https://fixture.invalid/login')), '');
assert.ok(!logs.some(line => /fixture-password|fixture-session-token|fixture@example|web-fixture-session/.test(line)), 'Credentials must not appear in diagnostics');
assert.deepEqual(unexpected, []);
assert.ok(!requests.some(r => /register|send|clear|add_book|user_settings/.test(r.path)));
const configFetches = () => requests.filter(r => r.path === '/static/source_config/config.json').length;
const beforeReset = configFetches();
unwrap(engine.loginAction({}, 'deleteVariable()'));
const resetForm = unwrap(engine.loginForm());
assert.equal(configFetches(), beforeReset + 1);
assert.equal(resetForm.values['频道（文字阅读）'], '男频');
assert.equal(resetForm.values['网络模式（文字阅读）'], '服务器');
assert.equal(resetForm.values['发现来源（文字阅读）'], '番茄');
assert.ok(resetForm.rows.find(r => r.name === '搜索来源（文字阅读）').chars.includes('测试平台'));
assert.match(engine.load({...source, bookSourceType: 1}).error, /text book/);
unwrap(engine.load({bookSourceUrl: 'https://browser-fixture.invalid', loginUi: '[{"name":"email","type":"text"}]', loginUrl: 'function login() { java.openUrl("https://browser-fixture.invalid/login"); }'}));
assert.equal(unwrap(engine.login({email: 'fixture@example.invalid'})).open, 'https://browser-fixture.invalid/login');
assert.match(engine.load({bookSourceUrl: 'https://broken.invalid', jsLib: 'throw new Error("broken library")'}).error, /jsLib/);
console.log('PASS: unchanged external Guangyu source; search/detail/catalog/text; discovery/reload; native text settings; fixture login failure/success/logout; Android HTML panel/media rejection; cookie handoff and log redaction. No live network or iOS runtime validation.');
