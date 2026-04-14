# Plan: #55 为 QueueController.put 接口增加请求入参与响应出参日志

## 目标

在 `QueueController.put` 方法中增加 info 级入参日志和出参日志，使每次 put 请求在线上日志中留下可追溯记录，便于排查入队异常和响应行为问题。

## 非目标

- 不对 `take`、`complete`、`register` 等其他方法补充日志（可后续独立处理）
- 不记录 `put.getData()` 的完整内容（避免日志过大，仅记录结构性字段）
- 不修改任何业务逻辑

## 验收标准

1. `put` 方法入口打印 info 日志，包含 `endpoint`、`queue`、`responseMode` 字段
2. 每个响应分支（blocking / streaming / callback）均在返回前打印 info 日志，包含 `taskId` 和实际 responseMode
3. 日志使用 `@Slf4j` 注解，与项目其他类保持一致
4. 现有测试全部通过，无回归

## 约束

- 日志级别统一使用 `info`
- 不记录 `put.getData()` 完整内容，避免敏感信息泄露和日志膨胀
- `@Slf4j` 注解方式与 `QueueService` 等保持一致

## 变更范围

| 文件 | 变更类型 |
|------|---------|
| `api/src/main/java/com/ke/bella/batch/api/QueueController.java` | 修改：添加 `@Slf4j` 注解 + `put` 方法增加入参/出参日志 |

## 实现思路

**目标**：为 `QueueController.put` 方法添加入参和出参日志。

**涉及文件**：`api/src/main/java/com/ke/bella/batch/api/QueueController.java`

**具体改动**：

1. 类声明上方添加 `@Slf4j` 注解，并补充对应 import：

```java
import lombok.extern.slf4j.Slf4j;
// ...
@Slf4j
@RestController
@RequestMapping("/v1/queue")
public class QueueController {
```

2. `put` 方法入口（Assert 校验之后、`qs.put(put)` 之前）添加入参日志：

```java
log.info("put request: endpoint={}, queue={}, responseMode={}", 
    put.getEndpoint(), put.getQueue(), put.getResponseMode());
```

3. 三个响应分支各自在 return 前添加出参日志：

```java
// blocking 分支
log.info("put response: taskId={}, responseMode=blocking, statusCode={}", 
    task.getTaskId(), statusCode);
return ResponseEntity.status(statusCode).body(payload);

// streaming 分支
log.info("put response: taskId={}, responseMode=streaming", task.getTaskId());
return callback.getEmitter();

// callback/默认分支
log.info("put response: taskId={}, responseMode={}", 
    task.getTaskId(), put.getResponseMode());
return BellaResponse.<String>builder()...
```

## 风险与依赖

- **风险极低**：纯日志添加，不改变任何业务逻辑
- `@Slf4j` 已是项目标准依赖（Lombok），无需新增依赖
- info 级日志在高并发场景下会略微增加日志量，但 put 接口本身就是每请求必经路径，属于预期范围