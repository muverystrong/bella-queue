-- 优化的 FIFO 策略脚本
-- 参数: ARGV[1]=maxSize, ARGV[2]=numQueues, ARGV[3..]=队列名列表

local maxSize = tonumber(ARGV[1])
local numQueues = tonumber(ARGV[2])

-- 第一步：批量预取所有队列的头部任务
local candidates = {}
for i = 1, numQueues do
    local queueKey = ARGV[2 + i]
    local metadataKey = queueKey .. ":metadata:"

    local batchSize = math.min(maxSize, 100)
    local queueTasks = redis.call('ZRANGE', queueKey, 0, batchSize - 1, 'WITHSCORES')

    -- 解析任务数据（ taskId, score 交替排列）
    for j = 1, #queueTasks, 2 do
        table.insert(candidates, {
            queueKey = queueKey,
            taskId = queueTasks[j],
            timestamp = tonumber(queueTasks[j + 1]),
            metadataKey = metadataKey
        })
    end
end

if #candidates == 0 then
    return {}
end

-- 第二步：按时间戳排序
table.sort(candidates, function(a, b)
    return a.timestamp < b.timestamp
end)

-- 第三步：按排序后的顺序批量获取任务
local limit = math.min(maxSize, #candidates)

-- 按 queueKey 分组
local queueGroups = {}
for i = 1, limit do
    local c = candidates[i]
    if not queueGroups[c.queueKey] then
        queueGroups[c.queueKey] = {metadataKey = c.metadataKey, taskIds = {}}
    end
    table.insert(queueGroups[c.queueKey].taskIds, c.taskId)
end

-- 批量 ZREM + MGET + UNLINK
local tasks = {}
local allMetadataKeys = {}
local allTaskIds = {}

for queueKey, group in pairs(queueGroups) do
    redis.call('ZREM', queueKey, unpack(group.taskIds))
    for _, taskId in ipairs(group.taskIds) do
        table.insert(allMetadataKeys, group.metadataKey .. taskId)
        table.insert(allTaskIds, taskId)
    end
end

if #allMetadataKeys > 0 then
    local taskJsons = redis.call('MGET', unpack(allMetadataKeys))
    redis.call('UNLINK', unpack(allMetadataKeys))

    for i, json in ipairs(taskJsons) do
        if json and #tasks < maxSize then
            table.insert(tasks, {allTaskIds[i], json})
        end
    end
end

return tasks
