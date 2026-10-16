# 使用 GitHub Actions 打包发布

工作流：`.github/workflows/release.yml`，名称为 **Build and Release**。

## 手动指定版本

先将工作流提交并推送到仓库默认分支 `main`，然后：

1. 打开仓库的 **Actions → Build and Release**。
2. 点击 **Run workflow**，分支选择 `main`。
3. 在 `version` 中输入 `v1.26.3` 或 `1.26.3`，点击运行。
4. 等待构建完成，在当前仓库的 **Releases → v1.26.3** 下载安装包。

生成两个安装包：

- `TaskTick-1.26.3-arm64.dmg`：Apple Silicon。
- `TaskTick-1.26.3-x86_64.dmg`：Intel。

如果版本标签已经存在，会构建该标签对应的源码；如果不存在，会构建本次运行所选分支的提交，并在构建成功后创建标签和 Release。重复运行会覆盖同名 Release 附件，并重新生成 Release 说明。已有版本要包含新的代码改动时，请使用新的版本号。

`v1.26.3` 已经有标签，即使标签里没有工作流，也可以从 `main` 手动运行并输入 `v1.26.3`。已有标签不会因为新增工作流而自动触发构建。

## 推送标签自动发布

工作流也会在推送新的 `v数字.数字.数字` 标签后自动运行，例如：

```bash
git tag -a v1.26.4 -m "新增功能和修复说明"
git push origin v1.26.4
```

标签应指向包含此工作流的提交。

## 自动生成 Release 说明

每次发布都会自动包含：

- **Tag 附注**：使用 `git tag -a ... -m "..."` 写入的版本说明，保留正文段落。轻量 tag 没有附注，会跳过这一部分。
- **提交记录**：沿当前发布分支的第一父提交历史寻找最近的上一个版本 tag，列出该 tag 到当前版本的全部提交，包括合并进来的提交。每条显示标题、作者和提交链接。
- **完整变更链接**和本次构建的源码提交。

找不到上一个版本 tag 时，列出当前版本的全部历史提交。上一个 tag 从 Git 历史中查找，不要求它已经创建 GitHub Release。

例如推送 `v1.26.4` 后，Release 中会展示 tag 的附注，以及 `v1.26.3..v1.26.4` 的提交记录。也可以直接使用 `git tag v1.26.4`，只生成提交记录。

## 构建和发布方式

- 使用 GitHub 托管的 `macos-15` runner，显式选择 Xcode 26.3，以编译项目使用的 macOS 26 API。
- 复用 `scripts/release.sh <版本号> --local-only` 打包，然后由工作流上传到运行该工作流的仓库。在本仓库中即 `Kerwin1202/TaskTick`。
- 使用 GitHub 自动提供的 `GITHUB_TOKEN`，工作流已声明 `contents: write`，通常不需要额外配置 Secret。Fork 仓库若尚未启用 Actions，需先在 Actions 页面启用。
- 安装包还会作为 Actions Artifact 保存 7 天；即使后续发布失败，也可以从该次运行页面下载已构建的包。
- 沿用现有脚本的 ad-hoc 签名，没有 Apple Developer ID 签名及公证；首次打开可能需要按 README 的方式放行。
