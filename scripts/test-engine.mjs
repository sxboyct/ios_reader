import vm from 'node:vm';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../Sources/TVCore/ScriptAssets');
const storage = new Map();
const pages = {
  'https://reader.example/search?q=test': '<div class="book"><a href="/book">测试小说</a><span class="author">作者</span></div>',
  'https://reader.example/book': '<h1>测试小说</h1><a class="chapter" href="/chapter1">第一章</a><a class="chapter" href="/chapter2">第二章</a>',
  'https://reader.example/chapter1': '<div id="content"><p>第一段文字。</p><p>第二段文字。</p></div>',
};
const context = vm.createContext({ console, URL, TextEncoder, TextDecoder });
context.__host = (op, argument) => {
  if (op === 'url') {
    const a = JSON.parse(argument), url = new URL(a.href, a.base || undefined);
    return JSON.stringify(Object.fromEntries(['href','origin','protocol','host','hostname','port','pathname','search','hash','username','password'].map(k => [k, url[k]])));
  }
  if (op === 'module') return fs.readFileSync(path.join(root, argument.replace('assets://', '')), 'utf8');
  if (op === 'md5') return crypto.createHash('md5').update(argument).digest('hex');
  if (op === 'novel.flag') return '';
  if (op === 'novel.log' || op === 'log') return null;
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
    assert.ok(pages[a.url], 'Unexpected network request: ' + a.url);
    return JSON.stringify({ url: a.url, code: 200, headers: { 'content-type': 'text/html; charset=utf-8' }, cookies: {}, base64: Buffer.from(pages[a.url]).toString('base64') });
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
unwrap(engine.load(JSON.stringify({ bookSourceUrl: 'https://reader.example', bookSourceName: 'Fixture', bookSourceType: 0,
  searchUrl: '/search?q={{key}}', ruleSearch: { bookList: 'class.book', name: 'tag.a@text', author: 'class.author@text', bookUrl: 'tag.a@href' },
  ruleBookInfo: { name: 'tag.h1@text', tocUrl: '@js:result = baseUrl' },
  ruleToc: { chapterList: 'class.chapter', chapterName: 'text', chapterUrl: 'href' },
  ruleContent: { content: 'id.content@text' }
})));
const results = unwrap(engine.search('test', 1));
assert.equal(results.length, 1); assert.equal(results[0].name, '测试小说');
const book = unwrap(engine.info(results[0]));
const toc = unwrap(engine.toc(book));
assert.equal(toc.chapters.length, 2); assert.equal(toc.chapters[0].title, '第一章');
const content = unwrap(engine.content(book, toc.chapters[0], toc.chapters[1]));
assert.ok(content.paragraphs.join('').includes('第一段文字。'));
assert.ok(content.paragraphs.join('').includes('第二段文字。'));
assert.deepEqual(unwrap(engine.rule('class.item@text', '<div class="item">第一段</div><div class="item">第二段</div>', 'https://example.com')), ['第一段', '第二段']);
assert.equal(engine.audio, undefined);
console.log('PASS: bundled modules, source loading, search, detail, catalog, chapter extraction, CSS rules, text-only API');
export { load, context, unwrap, pages };
