// Live diagnostic only. HTML and chapter text remain in process memory.
// Example: node --experimental-vm-modules scripts/inspect-suduguu.mjs --live --keyword 公考捡漏 --chapters 186,187,188
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { load, context, unwrap } from './test-engine.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const options = {};
for (let i = 2; i < process.argv.length; i++) {
    const key = process.argv[i];
    if (key === '--live') options.live = true;
    else if (['--keyword', '--title', '--chapters', '--source', '--report'].includes(key)) {
        if (!process.argv[i + 1] || process.argv[i + 1].startsWith('--')) throw Error('Missing value: ' + key);
        options[key.slice(2)] = process.argv[++i];
    } else throw Error('Unknown argument: ' + key);
}
if (!options.live) throw Error('Explicit --live required');
const keyword = options.keyword || '公考捡漏';
const requestedTitle = options.title || '公考捡漏：从女友抛弃到权利巅峰';
const numbers = (options.chapters || '186,187,188').split(',').map(Number);
if (!numbers.length || numbers.some(n => !Number.isSafeInteger(n) || n < 1)) throw Error('Invalid chapter numbers');
const sourcePath = path.resolve(root, options.source || '../suduguu.json');
const reportPath = path.resolve(root, options.report || 'Docs/suduguu-chapter-187.json');
const sha = value => createHash('sha256').update(value).digest('hex');
const fingerprint = value => ({ utf16: value.length, codePoints: [...value].length, sha256: sha(value) });
const normalized = value => value.replace(/\s/g, '');
const splitText = strings => strings.flatMap(t => t.split(/\r?\n/)).map(t => t.trim()).filter(Boolean);
const normalizeTitle = value => value.replace(/[\s\p{P}\p{S}]/gu, '');
const sourceBytes = fs.readFileSync(sourcePath);
const sourceObject = JSON.parse(sourceBytes);
if (Object.keys(sourceObject).length !== 1) throw Error('Expected exactly one alias');
const alias = Object.keys(sourceObject)[0], source = sourceObject[alias];
const adapterPath = path.join(root, 'Sources/TVCore/ScriptAssets/reader/xiangse.js');
const adapterBefore = sha(fs.readFileSync(adapterPath));
await (await load('assets://reader/engine.js')).evaluate();
const engine = context.__reader;
const cheerio = (await load('assets://js/lib/cheerio.min.js')).namespace;
const xpath = (await load('assets://legado/xpath.js')).namespace;
const originalHost = context.__host;
const responses = [];
const report = {
    startedAt: new Date().toISOString(), status: 'running',
    runtime: 'Node VM / curl; no official-app or iOS layout verification',
    userFontSetting: 'system', keyword, requestedTitle, requestedChapters: numbers,
    reproductionNote: 'User supplied 权力巅峰; the unique live search result uses 权利巅峰. Font layout is not executed by this network diagnostic.',
    source: { sha256: sha(sourceBytes), fixtureSHA256: sha(fs.readFileSync(path.join(root, 'Tests/Fixtures/suduguu.source.json'))) },
    adapterSHA256: adapterBefore,
    rules: { maxPage: source.chapterContent.moreKeys?.maxPage },
    textStorage: 'Memory only; report contains statistics, URLs and fingerprints, no chapter text',
    metrics: 'Lengths are UTF-16 unless codePoints is specified; SHA-256 over UTF-8; arrays hashed via JSON.stringify',
    chapters: [], findings: []
};
context.__host = (op, argument) => {
    if (op !== 'novel.http') return originalHost(op, argument);
    const request = JSON.parse(argument);
    const args = ['-L', '-sS', '--max-time', '20', '--max-filesize', '8388608', '-X', request.method || 'GET'];
    for (const [name, value] of Object.entries(request.headers || {})) args.push('-H', name + ': ' + value);
    if (request.body) args.push('--data-raw', request.body);
    const marker = '\n__READER_HTTP__';
    args.push('-w', marker + '%{http_code}|%{url_effective}', request.url);
    const output = execFileSync(process.platform === 'win32' ? 'curl.exe' : 'curl', args, { maxBuffer: 10 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
    const at = output.lastIndexOf(marker);
    if (at < 0) throw Error('Missing HTTP metadata');
    const [code, url] = output.subarray(at + marker.length).toString().split('|');
    const body = output.subarray(0, at);
    responses.push({ requestedURL: request.url, url, code: Number(code), bytes: body.length, sha256: sha(body), html: body.toString('utf8') });
    return JSON.stringify({ code: Number(code), url, base64: body.toString('base64'), headers: {}, cookies: {} });
};
function inspectPage(response) {
    const $ = cheerio.load(response.html);
    const extracted = splitText(xpath.select($.root()[0], source.chapterContent.content).map(xpath.asString));
    const paragraphs = $('div.con p').toArray();
    const nested = [];
    const full = [];
    const differences = [];
    for (let i = 0; i < paragraphs.length; i++) {
        const node = paragraphs[i];
        const direct = splitText(xpath.select(node, './text()').map(xpath.asString));
        const all = $(node).text().trim();
        full.push(all);
        const descendantText = $(node).children().toArray().map(n => $(n).text()).join('');
        if ($(node).children().length) nested.push({ index: i, childElements: $(node).children().length, descendantText: fingerprint(descendantText) });
        if (direct.join('') !== all) differences.push({ index: i, direct: fingerprint(direct.join('')), full: fingerprint(all),
            equalIgnoringWhitespace: normalized(direct.join('')) === normalized(all) });
    }
    const links = $('.prenext a').toArray().map(n => ({ label: $(n).text().trim(), href: $(n).attr('href') })).filter(n => n.href);
    const linkURL = label => { const item = links.find(n => n.label === label); return item ? new URL(item.href, response.url).href : null; };
    const selectedNext = xpath.select($.root()[0], source.chapterContent.nextPageUrl).map(xpath.asString).join('\n').trim();
    return { extracted, stats: {
        url: response.url, requestedURL: response.requestedURL, httpStatus: response.code, responseBytes: response.bytes, responseSHA256: response.sha256,
        titleSHA256: sha($('title').text()), paragraphElements: paragraphs.length, extractedParagraphs: extracted.length,
        extractedText: fingerprint(extracted.join('')), paragraphArraySHA256: sha(JSON.stringify(extracted)),
        fullParagraphText: fingerprint(full.join('')), equalIgnoringWhitespace: normalized(extracted.join('')) === normalized(full.join('')),
        nestedParagraphs: nested, directVsFullDifferences: differences,
        selectedNextPageURL: selectedNext ? new URL(selectedNext, response.url).href : null,
        visibleNextPageURL: linkURL('下一页'), previousPageURL: linkURL('上一页'), nextChapterURL: linkURL('下一章'), previousChapterURL: linkURL('上一章'),
        firstParagraph: fingerprint(extracted[0] || ''), lastParagraph: fingerprint(extracted.at(-1) || ''),
        head64: fingerprint(extracted.join('\n').slice(0, 64)), tail64: fingerprint(extracted.join('\n').slice(-64)),
        paragraphProfiles: extracted.map(t => ({ ...fingerprint(t), han: (t.match(/\p{Script=Han}/gu) || []).length,
            ascii: (t.match(/[\x00-\x7f]/g) || []).length, whitespace: (t.match(/\s/g) || []).length,
            punctuation: (t.match(/\p{P}/gu) || []).length }))
    } };
}
try {
    unwrap(engine.load(JSON.stringify({ bookSourceUrl: 'xiangse:' + source.sourceUrl + '#' + alias, _xiangse: source })));
    const found = unwrap(engine.search(keyword, 1, 30000));
    report.searchResults = found.map(b => ({ url: b.url, titleSHA256: sha(b.name) }));
    const matches = found.filter(b => normalizeTitle(b.name) === normalizeTitle(requestedTitle));
    if (matches.length !== 1) throw Error('Expected one exact normalized title match; got ' + matches.length);
    const book = unwrap(engine.info(matches[0], 30000));
    const toc = unwrap(engine.toc(book, 90000)).chapters;
    report.bookURL = book.url; report.catalogCount = toc.length;
    console.log(JSON.stringify({ event: 'book_matched', url: book.url, catalogCount: toc.length }));
    for (const number of numbers) {
        const matching = toc.filter(ch => new RegExp('^第\\s*' + number + '\\s*章(?:\\s|$|[^0-9])').test(ch.title));
        if (matching.length !== 1) throw Error('Chapter lookup failed: ' + number + ', matches=' + matching.length);
        const chapter = matching[0], index = toc.indexOf(chapter), next = toc[index + 1];
        const start = responses.length;
        const answer = engine.content(book, chapter, next, 45000);
        const inspected = responses.slice(start).map(inspectPage);
        const expected = inspected.flatMap(p => p.extracted);
        const actual = answer.value?.paragraphs || [];
        const entry = { number, url: chapter.url, titleSHA256: sha(chapter.title), nextChapterURL: next?.url,
            status: answer.error ? 'engine_error' : 'completed', error: answer.error || null,
            pageCount: inspected.length, pages: inspected.map(p => p.stats),
            paragraphs: actual.length, paragraphUTF16Lengths: actual.map(t => t.length),
            firstParagraph: fingerprint(actual[0] || ''), lastParagraph: fingerprint(actual.at(-1) || ''),
            text: fingerprint(actual.join('')), paragraphArraySHA256: sha(JSON.stringify(actual)),
            exactOrderedMerge: !answer.error && JSON.stringify(actual) === JSON.stringify(expected),
            allParagraphTextPreservedIgnoringWhitespace: inspected.every(p => p.stats.equalIgnoringWhitespace),
            pageLinksContinuous: inspected.every((p, i) => i === inspected.length - 1 ? !p.stats.selectedNextPageURL && !p.stats.visibleNextPageURL : p.stats.selectedNextPageURL === inspected[i + 1].stats.url),
            finalNextChapterMatchesCatalog: !!next && inspected.at(-1)?.stats.nextChapterURL === next.url,
            boundaries: inspected.slice(1).map((p, i) => ({ fromURL: inspected[i].stats.url, toURL: p.stats.url,
                mergedParagraphOffset: inspected.slice(0, i + 1).reduce((sum, x) => sum + x.extracted.length, 0),
                previousLast: inspected[i].stats.lastParagraph, nextFirst: p.stats.firstParagraph,
                previousLinkMatches: p.stats.previousPageURL === inspected[i].stats.url,
                identicalAdjacentParagraph: inspected[i].extracted.at(-1) === p.extracted[0] }))
        };
        report.chapters.push(entry);
        if (!entry.exactOrderedMerge || !entry.allParagraphTextPreservedIgnoringWhitespace || !entry.pageLinksContinuous || !entry.finalNextChapterMatchesCatalog) {
            report.findings.push({ chapter: number, mergeMismatch: !entry.exactOrderedMerge, textMismatch: !entry.allParagraphTextPreservedIgnoringWhitespace,
                navigationMismatch: !entry.pageLinksContinuous, nextChapterMismatch: !entry.finalNextChapterMatchesCatalog });
        }
        console.log(JSON.stringify({ event: 'chapter_checked', number, pages: entry.pageCount, paragraphs: entry.paragraphs,
            characters: entry.text.utf16, exactOrderedMerge: entry.exactOrderedMerge,
            fullParagraphTextPreserved: entry.allParagraphTextPreservedIgnoringWhitespace,
            pageLinksContinuous: entry.pageLinksContinuous, finalNextChapterMatchesCatalog: entry.finalNextChapterMatchesCatalog,
            nestedParagraphs: entry.pages.reduce((sum, p) => sum + p.nestedParagraphs.length, 0) }));
    }
    report.status = report.findings.length ? 'findings' : 'sample_network_content_checks_pass';
} catch (error) {
    report.status = 'blocked_or_failed';
    report.error = String(error.message);
    process.exitCode = 1;
} finally {
    report.chapterBoundaries = report.chapters.slice(1).map((chapter, i) => ({
        from: report.chapters[i].number, to: chapter.number,
        fromPageCount: report.chapters[i].pageCount, toPageCount: chapter.pageCount,
        previousLast: report.chapters[i].lastParagraph, nextFirst: chapter.firstParagraph,
        nextChapterURLMatches: report.chapters[i].nextChapterURL === chapter.url
    }));
    report.sharedTailHashes = [...new Set(report.chapters.map(c => c.lastParagraph.sha256))].map(hash => ({
        sha256: hash, chapters: report.chapters.filter(c => c.lastParagraph.sha256 === hash).map(c => c.number)
    })).filter(group => group.chapters.length > 1);
    report.requests = responses.map(({ html, ...metadata }) => metadata);
    report.finishedAt = new Date().toISOString();
    report.sourceUnchanged = sha(fs.readFileSync(sourcePath)) === report.source.sha256;
    report.adapterUnchangedDuringRun = sha(fs.readFileSync(adapterPath)) === adapterBefore;
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({ event: 'report_written', status: report.status, path: reportPath, error: report.error }));
}
