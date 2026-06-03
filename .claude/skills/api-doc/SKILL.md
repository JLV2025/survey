---
name: api-doc
description: 为指定的 API 端点生成文档，提取路径、方法、参数及请求/响应结构
disable-model-invocation: true
---

为 $ARGUMENTS 生成 API 文档。

## 步骤

1. 阅读目标 handler 代码，提取路由路径、HTTP 方法、参数
2. 追踪请求体及响应数据的结构（model 类型）
3. 按以下格式输出文档：

```markdown
## {METHOD} {PATH}

**描述**: [简要说明]

**请求参数**:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|

**请求体**: (如适用)
```json
{ ... }
```

**响应**:
```json
{ "data": ..., "error": "" }
```
```
