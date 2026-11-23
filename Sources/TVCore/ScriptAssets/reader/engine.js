import 'assets://legado/engine.js';
import { xiangse } from 'assets://reader/xiangse.js';

let active = globalThis.__legado;
globalThis.__reader = {
    load(text) {
        try {
            const source = JSON.parse(text);
            active = source._xiangse ? xiangse : globalThis.__legado;
            return active.load(text);
        } catch (error) { return { error: String(error.message || error) }; }
    }
};
for (const name of ['search', 'info', 'toc', 'content', 'exploreKinds', 'explore', 'loginForm', 'login', 'loginAction', 'logout', 'keepCookies']) {
    globalThis.__reader[name] = (...args) => active[name] ? active[name](...args) : { error: '此香色书源操作暂不支持：' + name };
}
