// Xiangse DOM/HTML compatibility adapter. Original rules are kept intact, not rewritten as Legado.
import * as cheerio from 'assets://js/lib/cheerio.min.js';
import * as XPath from 'assets://legado/xpath.js';

let source, key, deadline;
const host = (op, args) => globalThis.__host(op, typeof args === 'string' ? args : JSON.stringify(args));
const text = value => Array.isArray(value) ? value.map(text).join('\n') : value == null ? '' : String(value);
const array = value => Array.isArray(value) ? value : [value];
function absolute(value, base) {
    value = text(value).trim();
    if (!value || /\s/.test(value)) throw Error('书源没有返回单一有效网址：' + value);
    const url = new URL(value, base);
    if (!/^https?:$/.test(url.protocol)) throw Error('书源网址只支持 HTTP / HTTPS');
    return url.href;
}
function config(action) { return { ...source, ...action, host: action.host || source.sourceUrl,
    httpHeaders: { ...(source.httpHeaders || {}), ...(action.httpHeaders || {}) } }; }
function javascript(rule, action, params, result) {
    return Function('config', 'params', 'result', rule.slice(4))(config(action), params, result);
}
function parts(rule) {
    if (rule.includes('||')) return rule.split('||');
    if (rule.includes('|') && /@js:|@replace:|%@result/.test(rule)) return rule.split('|');
    return [rule]; // A plain XPath union is one expression.
}
function values(rule, document, action, params, initial) {
    if (!rule) return [];
    const segments = parts(String(rule));
    let result = initial, hasValue = false;
    for (let i = 0; i < segments.length; i++) {
        let segment = segments[i].trim();
        if (segment.startsWith('@js:')) {
            result = javascript(segments.slice(i).join(rule.includes('||') ? '||' : '|').trim(), action, params, text(result));
            break;
        }
        if (segment.includes('@replace:')) {
            const at = segment.indexOf('@replace:');
            result = text(result).replace(new RegExp(segment.slice(at + 9), 'g'), segment.slice(0, at));
        } else if (segment.includes('%@result')) result = segment.replaceAll('%@result', text(result));
        else if (!hasValue || !text(result)) {
            segment = segment.replace(/^@path:/, '');
            result = array(XPath.select(document, segment)).map(XPath.asString);
        }
        hasValue = true;
    }
    return (Array.isArray(result) ? result : [result]).filter(v => v != null).map(text);
}
function field(action, name, document, params) { return values(action[name], document, action, params).join('\n').trim(); }
function validate(action) {
    if (!action || action.parserID !== 'DOM' || action.responseFormatType !== 'html') throw Error('目前支持香色 DOM / html 规则');
    for (const name of ['webView', 'webViewSniff', 'webViewContentRules', 'responseDecryptType', 'JSParser', 'requestJavascript', 'responseJavascript', 'requestFunction', 'responseFunction']) {
        if (action[name]) throw Error('暂不支持香色能力：' + name);
    }
    if (action.validConfig) throw Error('暂不支持香色 validConfig 校验规则');
}
function request(action, params, result, next) {
    validate(action);
    let info;
    if (next) info = { url: next };
    else if (action.requestInfo.startsWith('@js:')) info = javascript(action.requestInfo, action, params, result);
    else info = action.requestInfo.replaceAll('%@result', result || '');
    if (typeof info === 'string') info = { url: info };
    if (!info || typeof info !== 'object') throw Error('requestInfo 没有返回网址或请求对象');
    info = { ...action, ...info };
    validate(info);
    let url = absolute(info.url, action.host || source.sourceUrl);
    const method = info.POST ? 'POST' : 'GET';
    if (method === 'POST' && String(info.requestParamsEncode || action.requestParamsEncode || '').includes('2147485234')) throw Error('暂不支持 GBK POST 参数编码');
    const headers = { ...config(action).httpHeaders, ...(info.httpHeaders || {}) };
    const httpParams = info.httpParams;
    let body;
    if (httpParams != null) {
        body = typeof httpParams === 'string' ? httpParams : Object.entries(httpParams).map(([k,v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v)).join('&');
        if (method === 'GET') { url += (url.includes('?') ? '&' : '?') + body; body = undefined; }
        else if (!Object.keys(headers).some(k => k.toLowerCase() === 'content-type')) headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    if (Date.now() >= deadline) throw Error('香色书源请求超时');
    const response = JSON.parse(host('novel.http', { url, method, headers, body, jar: key, forbidCookie: Boolean(info.forbidCookie), forbidCache: Boolean(info.forbidCache), timeout: Math.min(15000, deadline - Date.now()) }));
    if (response.failed || response.code < 200 || response.code >= 300) throw Error(response.failed || ('HTTP ' + response.code));
    const encoding = info.responseEncode || action.responseEncode;
    const html = host('novel.decode', { base64: response.base64, encoding: ['2147485232','2147485234'].includes(String(encoding)) ? 'gb18030' : 'utf-8' });
    return { document: cheerio.load(html).root()[0], url: absolute(response.url || url, url) };
}
function query(book, chapter) {
    const saved = book?.variables?.xiangseQuery;
    let original = {}; try { original = JSON.parse(saved || '{}'); } catch {}
    return { ...original, bookName: book?.name, author: book?.author, detailUrl: book?.url,
        ...(chapter ? { title: chapter.title, url: chapter.url, detailUrl: chapter.url } : { url: book?.url }) };
}
function page(action, params, result, next) {
    const response = request(action, params, result, next);
    params.responseUrl = response.url; params.requestInfo = response.url;
    return response;
}
function bookFields(action, document, params) {
    const item = {};
    for (const name of ['bookName','author','cover','detailUrl','desc','cat','status','wordCount','lastChapterTitle','chapterListUrl']) item[name] = field(action, name, document, params);
    for (const name of ['cover','detailUrl','chapterListUrl']) if (item[name]) item[name] = absolute(item[name], params.responseUrl);
    return item;
}
function toBook(item, old = {}) {
    return { ...old, sourceKey: key, url: item.detailUrl || old.url, name: item.bookName || old.name || '',
        author: item.author || old.author || '', cover: item.cover || old.cover || '', intro: item.desc || old.intro || '',
        kind: item.cat || old.kind || '', wordCount: item.wordCount || old.wordCount || '',
        lastChapter: item.lastChapterTitle || old.lastChapter || '', tocURL: item.chapterListUrl || old.tocURL || item.detailUrl || old.url,
        variables: { ...(old.variables || {}), xiangseQuery: JSON.stringify(item) }, isAudio: false };
}
function run(budget, fn) {
    deadline = Date.now() + (Number(budget) || 45000);
    try { return { value: fn() }; } catch (error) { return { error: String(error.message || error) }; }
}
function pages(action, params, result, consume) {
    const seen = new Set(); let next, last = {};
    const max = Math.min(50, Math.max(1, Number(action.moreKeys?.maxPage) || 10));
    for (let i = 0; i < max; i++) {
        params.pageIndex = i + 1; params.lastResponse = last;
        if (next && params.stopAt && next === params.stopAt) throw Error('分页链接指向下一章，已停止');
        const response = page(action, params, result, next);
        if (seen.has(response.url)) throw Error('书源分页出现循环');
        seen.add(response.url); consume(response.document);
        const link = field(action, 'nextPageUrl', response.document, params);
        if (!link || link.startsWith('#')) return;
        next = absolute(link, response.url); last = { nextPageUrl: next }; result = next;
        if (seen.has(next)) throw Error('书源分页出现循环');
    }
    throw Error('书源分页超过 maxPage 限制，正文或目录尚未完整');
}
export const xiangse = {
    load(json) { return run(1000, () => {
        const wrapper = JSON.parse(json); source = wrapper._xiangse; key = wrapper.bookSourceUrl;
        if (!source || source.sourceType !== 'text') throw Error('不是香色文字书源');
        for (const name of ['searchBook','bookDetail','chapterList','chapterContent']) validate(source[name]);
        return true;
    }); },
    search(keyword, pageIndex, budget) { return run(budget, () => {
        const action = source.searchBook, params = { keyWord: keyword, pageIndex: pageIndex || 1, queryInfo: {} };
        const response = page(action, params, '');
        return XPath.select(response.document, action.list).map(node => {
            // Xiangse evaluates // child fields against the isolated list item, including its own element.
            const fragment = cheerio.load(XPath.outerHTML(node)).root()[0];
            return toBook(bookFields(action, fragment, params));
        }).filter(book => book.name && book.url);
    }); },
    info(book, budget) { return run(budget, () => {
        const action = source.bookDetail, params = { queryInfo: query(book), pageIndex: 1 };
        const response = page(action, params, book.url);
        return toBook(bookFields(action, response.document, params), book);
    }); },
    toc(book, budget) { return run(budget, () => {
        const action = source.chapterList, params = { queryInfo: query(book) }, chapters = [], seen = new Set();
        pages(action, params, book.tocURL || book.url, document => {
            for (const node of XPath.select(document, action.list)) {
                const fragment = cheerio.load(XPath.outerHTML(node)).root()[0];
                const url = absolute(field(action, 'url', fragment, params) || field(action, 'detailUrl', fragment, params), params.responseUrl);
                const title = field(action, 'title', fragment, params);
                if (!title || seen.has(url)) continue;
                seen.add(url); chapters.push({ index: chapters.length, title, url, isVolume: false, isVip: false, tag: '', variables: {} });
            }
        });
        return { chapters };
    }); },
    content(book, chapter, nextChapter, budget) { return run(budget, () => {
        const action = source.chapterContent, params = { queryInfo: query(book, chapter), stopAt: nextChapter?.url }, paragraphs = [];
        pages(action, params, chapter.url, document => {
            if (nextChapter?.url && params.responseUrl === nextChapter.url) throw Error('分页链接指向下一章，已停止');
            const extracted = values(action.content, document, action, params).flatMap(t => t.split(/\r?\n/)).map(t => t.trim()).filter(Boolean);
            if (!extracted.length) throw Error('正文第 ' + params.pageIndex + ' 页为空，章节尚未完整，请重试或检查书源');
            paragraphs.push(...extracted);
        });
        return { title: chapter.title, paragraphs };
    }); }
};
