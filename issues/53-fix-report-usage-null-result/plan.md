# Plan: #53 修复 reportUsage 缺少 result 空值防护导致潜在 NPE

## 目标

在 `QueueService.reportUsage(Task, Map<String, Object>)` 入口处增加 `result == null` 的防护判断，消除因上游传入 null 时触发的 NPE，确保费用上报链路在异常场景下安全降级并留下可观测日志。

## 非目标

- 不修改 `complete()` 方法签名或调用方行为
- 不处理 `result` 中 `BODY` key 缺失（值为 null）的情况，仅处理 `result` 本身为 null
- 不引入任何新的外部依赖

## 验收标准

1. 当 `result == null` 时，`reportUsage` 提前 return，不抛出 NPE
2. 提前 return 时打印 warn 日志，携带 `taskId` 字段
3. 正常路径（`result != null`）行为与修改前完全一致
4. 现有测试全部通过，无回归

## 约束

- 仅改动 `QueueService.java` 单一文件
- 日志级别使用 `warn`（与现有 `channel == null` 的处理保持一致）
- 不改变方法签名、访问权限或返回类型

## 变更范围

| 文件 | 变更类型 |
|------|---------|
| `api/src/main/java/com/ke/bella/batch/service/QueueService.java` | 修改：`reportUsage(Task, Map)` 方法入口增加 null 防护 |

## 实现思路

**目标**：在 `reportUsage(Task, Map<String, Object>)` 方法（L280）入口的 `channel == null` 判断之前增加 `result == null` 防护。

**涉及文件**：`api/src/main/java/com/ke/bella/batch/service/QueueService.java`

**具体改动**：

```java
// 修改前（L280）
private void reportUsage(Task task, Map<String, Object> result) {
    Channel channel = OpenapiUtils.getChannelByQueue(task.getQueue());
    if(channel == null) {
        return;
    }

// 修改后
private void reportUsage(Task task, Map<String, Object> result) {
    if(result == null) {
        log.warn("result is null, skip usage report for taskId: {}", task.getTaskId());
        return;
    }
    Channel channel = OpenapiUtils.getChannelByQueue(task.getQueue());
    if(channel == null) {
        return;
    }
```

将 `result == null` 的检查置于 `channel == null` 之前，因为 result 是调用方传入参数，防护应在任何业务逻辑之前完成。

## 风险与依赖

- **风险极低**：改动仅为防御性 guard，不影响正常路径
- **现有调用分析**：
  - 超时回调路径（L446）：构造了非 null 的 `HashMap`，不受影响
  - HTTP API 路径（`QueueController.java:116`）：`@RequestBody` 反序列化保证非 null，不受影响
  - 两处 `submitUsage` 调用（L244、L268）均来自 `complete()` 方法，result 可能为 null 的场景有限，但防护有必要
- **无外部依赖**，无需修改测试基础设施
