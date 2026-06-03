---
name: setup-dev
description: 为本项目配置开发环境
disable-model-invocation: true
---

为本项目配置开发环境。

## 前置条件

- Go 1.21+
- 已安装 `gofmt`、`go build` 工具链

## 步骤

1. **检查 Go 版本**: `go version`
2. **下载依赖**: `go mod download`
3. **验证构建**: `go build ./...`
4. **启动开发服务器**: `go run main.go`
   - 默认监听 `:8080`
   - 前端静态文件位于 `web/` 目录

## 常见问题

- **端口冲突**: 修改 `config.json` 中的端口配置
- **依赖下载失败**: 检查 GOPROXY 设置 `go env GOPROXY`
- **前端不更新**: 清除浏览器缓存，前端文件直接由 Go 服务提供静态服务
