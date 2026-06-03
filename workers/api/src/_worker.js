// Cloudflare Pages Functions 入口
// Pages Functions 只支持 _worker.js（不支持 _worker.ts 编译），
// 所以用 JS 文件重新导出 index.ts 中的默认 handler。
// wrangler pages deploy 会自动编译 TypeScript 并打包依赖。
export { default } from './index';