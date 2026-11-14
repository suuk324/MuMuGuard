# GitHub Actions CI（暂未启用）

因为当前 gh token 没有 workflow 权限，这个文件没放在 .github/workflows/ 下，避免推送被拒绝。

## 启用方法

1. 给 gh 授权 workflow 权限：
   `
   gh auth refresh -h github.com -s workflow
   `
2. 把文件放回正确位置：
   `
   mkdir .github\workflows
   move build\github-actions\ci.yml .github\workflows\ci.yml
   git add .github && git commit -m "启用 CI" && git push
   `

启用后每次推送会自动跑：编码检查 → 语法检查 → 54 个单元测试 → 打包冒烟。
