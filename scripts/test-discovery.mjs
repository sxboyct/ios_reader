// Synthetic regression cases run in CI without redistributing a third-party source.
import assert from 'node:assert/strict';
import {load, context, unwrap} from './test-engine.mjs';
await (await load('assets://reader/engine.js')).evaluate();
const engine = context.__reader;
const source = {
    bookSourceUrl: 'https://discovery.example', bookSourceName: 'Discovery fixture', bookSourceType: 0,
    jsLib: 'const {sourceHeading} = {sourceHeading: "发现分类"};\nconst chosen = source.getVariable() || "男频";',
    exploreUrl: '@js:JSON.stringify([{title: sourceHeading + chosen, url: "https://discovery.example/list"}])',
    searchUrl: '@js:"data:application/json," + encodeURIComponent(JSON.stringify({data:[{name:chosen,url:"https://discovery.example/book"}]}))',
    ruleSearch: {bookList: '$.data', name: '$.name', bookUrl: '$.url'},
    loginUi: JSON.stringify([{name: '邮箱', type: 'text'}, {name: '密码', type: 'password'},
        {name: '线路', type: 'button', action: 'source.setVariable("女频")', style: {layout_flexBasisPercent: 1}}]),
    loginUrl: 'function login() { java.startBrowser("https://discovery.example/login"); }'
};
unwrap(engine.load(JSON.stringify(source)));
assert.equal(unwrap(engine.exploreKinds())[0].title, '发现分类男频');
assert.equal(unwrap(engine.search('fixture', 1))[0].name, '男频');
assert.equal(unwrap(engine.loginForm()).rows[2].wide, true);
assert.equal(unwrap(engine.login({})).open, undefined); // An empty form does not open a browser.
assert.equal(unwrap(engine.login({'邮箱': 'fixture@example.invalid'})).open, 'https://discovery.example/login');
assert.equal(unwrap(engine.loginAction({}, 'java.startBrowserAwait("https://discovery.example/user")')).open, 'https://discovery.example/user');
unwrap(engine.loginAction({}, 'source.setVariable("女频")'));
unwrap(engine.load(JSON.stringify(source)));
assert.equal(unwrap(engine.search('fixture', 1))[0].name, '女频');
assert.equal(unwrap(engine.exploreKinds())[0].title, '发现分类女频');
unwrap(engine.keepCookies('https://discovery.example/login', 'session=fixture; old=value'));
assert.match(unwrap(engine.loginCookies('https://discovery.example')), /session=fixture/);
unwrap(engine.keepCookies('https://discovery.example/login', 'session=new'));
assert.equal(unwrap(engine.loginCookies('https://discovery.example')), 'session=new');
unwrap(engine.keepCookies('https://discovery.example/login', ''));
assert.equal(unwrap(engine.loginCookies('https://discovery.example')), '');
unwrap(engine.load(JSON.stringify({...source, bookSourceUrl: 'https://separate.example'})));
assert.equal(unwrap(engine.exploreKinds())[0].title, '发现分类男频');
// Binary typed data URLs are hex strings; ordinary data URLs stay UTF-8.
const payload = Buffer.from('中文正文').toString('base64');
const dataSource = {...source, jsLib: '', ruleContent: {content: '@js:java.hexDecodeToString(result)'}};
unwrap(engine.load(JSON.stringify(dataSource)));
const chapter = {title: '测试章节', url: `data:;base64,${payload},{"type":"fixture"}`};
assert.deepEqual(unwrap(engine.content({url: 'https://discovery.example/book'}, chapter, null)).paragraphs, ['中文正文']);
unwrap(engine.load(JSON.stringify({...dataSource, ruleContent: {content: '@js:result'}})));
assert.deepEqual(unwrap(engine.content({url: 'https://discovery.example/book'}, {...chapter, url: `data:;base64,${payload}`}, null)).paragraphs, ['中文正文']);
console.log('PASS: discovery settings reload, shared jsLib declarations, form layout, visible login handoff, cookie replacement/isolation and typed data URLs');
