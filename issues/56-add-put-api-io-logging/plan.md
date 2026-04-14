# Plan: #56 为 PUT 接口添加请求与响应日志

## 目标

在 `QueueController#put` 方法中增加结构化 info 级日志，记录请求入参（endpoint、queue、responseMode）和响应出参（taskId、最终 responseMode 分支），提升线上可观测性，缩短排查时间。

## 非目标

- 不修改 `take`、`complete`、`register` 等其他方法的日志（可作独立 Issue）
- 不引入链路追踪（tracing）或 MDC 上下文
- 不对 `data` 字段做日志输出（避免敏感/大体积内容污染日志）

## 验收标准

1. 调用 `PUT /v1/queue/put` 后，日志中可见以下两条 info 日志：
   - 请求日志：包含 `endpoint`、`queue`（可为 null）、`responseMode`
   - 响应日志：包含 `taskId`、`responseMode` 及分支信息（callback/blocking/streaming）
2. 日志格式与项目现有风格一致（`@Slf4j` + `log.info(...)`）
3. 不影响现有业务逻辑，不改变任何接口返回值

## 约束

- 日志级别固定为 `info`
- 使用 Lombok `@Slf4j`，与现有代码风格一致
- 不打印 `put.getData()` 内容

## 变更范围

| 文件 | 操作 |
|------|------|
| `api/src/main/java/com/ke/bella/batch/api/QueueController.java` | 修改：添加 `@Slf4j` 注解 + 2 处 `log.info` 调用 |

## 实现思路

**步骤 1**：为 `QueueController` 添加 `@Slf4j` 注解

```java
@Slf4j
@RestController
@RequestMapping("/v1/queue")
public class QueueController {
```

**步骤 2**：在 `put` 方法入参校验通过后、调用 `qs.put(put)` 之前，添加请求日志

```java
log.info("put request: endpoint={}, queue={}, responseMode={}",
    put.getEndpoint(), put.getQueue(), put.getResponseMode());
```

**步骤 3**：在 `qs.put(put)` 返回 `task` 之后、进入响应模式判断之前，添加响应日志

```java
log.info("put response: taskId={}, responseMode={}",
    task.getTaskId(), put.getResponseMode());
```

最终 `put` 方法结构：
```
校验入参
→ log.info("put request: ...")
→ qs.put(put)  → task
→ log.info("put response: ...")
→ 按 responseMode 分支返回
```

## 风险与依赖

- 无外部依赖，`lombok` 已在项目中使用
- `put.getQueue()` 可能为 null（endpoint + queue 均已由 QueueService 内部处理），日志中直接输出 null 即可，无需特殊处理
- 低风险：纯新增日志，不改变任何业务逻辑