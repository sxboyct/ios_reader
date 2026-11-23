import { load, context, unwrap, pages } from './test-engine.mjs';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const source = JSON.parse(fs.readFileSync(new URL('../Tests/Fixtures/suduguu.source.json', import.meta.url), 'utf8'))['suduguu-v1'];
const wrapper = { bookSourceUrl: 'xiangse:' + source.sourceUrl + '#suduguu-v1', _xiangse: source };
await (await load('assets://reader/engine.js')).evaluate();
const engine = context.__reader;
const live = process.argv.includes('--live');
const requests = [];
if (live) {
    const originalHost = context.__host;
    context.__host = (op, argument) => {
        if (op !== 'novel.http') return originalHost(op, argument);
        const request = JSON.parse(argument);
        const args = ['-L', '-sS', '--max-time', '20', '--max-filesize', '8388608', '-X', request.method || 'GET'];
        for (const [name, value] of Object.entries(request.headers || {})) args.push('-H', name + ': ' + value);
        if (request.body) args.push('--data-raw', request.body);
        args.push('-w', '\n__READER_HTTP__%{http_code}|%{url_effective}', request.url);
        const output = execFileSync(process.platform === 'win32' ? 'curl.exe' : 'curl', args, { maxBuffer: 10 * 1024 * 1024 });
        const at = output.lastIndexOf('\n__READER_HTTP__');
        assert.ok(at >= 0);
        const [code, url] = output.subarray(at + '\n__READER_HTTP__'.length).toString().split('|');
        const body = output.subarray(0, at);
        requests.push({ requestedURL: request.url, responseURL: url, code: Number(code), bytes: body.length });
        return JSON.stringify({ code: Number(code), url, base64: body.toString('base64'), headers: {}, cookies: {} });
    };
} else {
    pages['https://www.suduguu.com/i/sor.aspx?key=%E9%83%BD%E5%B8%82'] = '<div class="item"><a><img src="/cover.jpg"></a><div class="itemtxt"><h3><a href="/book/">都市测试</a></h3><p>状态</p><p><a>作者甲</a></p></div></div><div class="item"><div class="itemtxt"><h3><a href="/other/">都市另一本</a></h3><p>状态</p><p><a>作者乙</a></p></div></div>';
    pages['https://www.suduguu.com/book/'] = '<div class="item"><div class="itemtxt"><h1><a>都市测试</a><i>10万字</i></h1><p><span>连载</span><span>都市</span></p><p><a>作者甲</a></p></div></div><div class="des"><p>简介</p></div><div id="list"><ul><li><a href="1.html">第一章</a></li><li><a href="2.html">第二章</a></li></ul></div>';
    pages['https://www.suduguu.com/book/1.html'] = '<div class="con"><p>第一页甲</p><p>第一页乙</p></div><div class="prenext"><a href="1_2.html">下一页</a></div>';
    pages['https://www.suduguu.com/book/1_2.html'] = '<div class="con"><p>第二页丙</p></div><div class="prenext"><a href="2.html">下一章</a></div>';
}
unwrap(engine.load(JSON.stringify(wrapper)));
const found = unwrap(engine.search('都市', 1, 30000));
assert.ok(found.length > 0); assert.ok(found[0].name); assert.ok(found[0].author);
if (!live) { assert.equal(found.length, 2); assert.equal(found[0].author, '作者甲'); assert.equal(found[1].author, '作者乙'); }
const book = unwrap(engine.info(found[0], 30000));
assert.ok(book.name); if (!live) assert.ok(book.intro);
const toc = unwrap(engine.toc(book, 90000)).chapters;
assert.ok(toc.length > 0); assert.ok(toc[0].title); assert.match(toc[0].url, /^https:\/\//);
const content = unwrap(engine.content(book, toc[0], toc[1], 45000));
assert.ok(content.paragraphs.length > 0);
if (live) {
    assert.ok(content.paragraphs.join('').length > 100);
    const report = { test: 'Reader Xiangse adapter live network chain (curl host, Node VM)', date: new Date().toISOString(),
        adapterNetworkCheck: 'pass', officialAppCheck: 'blocked', iOSRuntimeCheck: 'not_run',
        blockedReason: 'Official StandarReader 2.56.1 provenance/runtime and iOS/Xcode are unavailable. This is not official-app acceptance.',
        name: book.name, searchResults: found.length, chapterCount: toc.length, paragraphs: content.paragraphs.length,
        characters: content.paragraphs.join('').length,
        warnings: [
            ...(!book.intro ? ['The supplied bookDetail.desc rule returned no introduction on the live page; source was not modified.'] : []),
            ...(!source.chapterList.nextPageUrl ? ['The supplied chapterList has no nextPageUrl; only the returned catalog page is read.'] : [])
        ], requests };
    fs.writeFileSync(new URL('../Docs/xiangse-live.json', import.meta.url), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
} else {
    assert.deepEqual(content.paragraphs, ['第一页甲','第一页乙','第二页丙']);
    pages['https://www.suduguu.com/book/1_2.html'] = '<div class="con"><p>循环</p></div><div class="prenext"><a href="1.html">下一页</a></div>';
    assert.match(engine.content(book, toc[0], toc[1]).error, /循环/);
    pages['https://www.suduguu.com/book/1_2.html'] = '<div class="con"><p>跨章</p></div><div class="prenext"><a href="2.html">下一页</a></div>';
    pages['https://www.suduguu.com/book/2.html'] = '<div class="con"><p>下一章</p></div>';
    assert.match(engine.content(book, toc[0], toc[1]).error, /下一章/);
    const unsupported = structuredClone(wrapper); unsupported._xiangse.chapterContent.webViewSniff = '.*';
    assert.match(engine.load(JSON.stringify(unsupported)).error, /不支持/);
    console.log('PASS: unchanged user Xiangse source, item-scoped XPath, URL propagation, search/detail/catalog/content, two-page merge, cycle/cross-chapter guard, unsupported capability rejection');
}
