目标不是讲技术炫不炫，而是向合规 / 风控 / 审计解释：为什么这个设计“天然符合澳洲金融监管预期”。

我会用 “监管关心什么 → 你的设计如何一一满足” 的方式来讲，这是审计最容易买单的结构。

一句话总论（你可以先说）

这个架构之所以能过审，是因为它把 APRA 和 Privacy Act 的核心要求——
“最小暴露、强控制、可追溯、可重现”——内建到了数据生命周期里，而不是事后补救。

一、监管审计真正关心的 6 个问题

在 Australian Ethical 这样的机构，审计人员本质上只问 6 件事：

敏感数据有没有被不必要地暴露？

谁在什么时候访问了什么数据？

数据有没有被篡改或静默出错？

出问题能不能快速定位和止损？

历史结果能不能重算并解释？

密钥和权限是不是集中、可控、可审计？

你这套设计，是“逐条命中”这些问题的。

二、为什么“加密 Parquet → 受控解密 → Snowflake”能过审
审计视角

“你们什么时候、在哪里、以什么方式接触明文？”

你的设计回答

加密文件 只在 Azure Blob 中以密文存在

解密只发生在受控计算环境

解密产物：

不长期存放

不暴露给非工程角色

有明确 run_id / batch_id

为什么合规

满足 Privacy Act（最小化暴露）

满足 APRA CPS 234（信息资产保护）

密钥不在代码、不在 DAG、不在变量里（Key Vault）

👉 审计结论：“明文存在范围最小，风险可控”

三、为什么 Airflow + dbt 是“审计友好”的，而不是只是工程选择
1️⃣ Airflow：业务时间轴 & 责任边界清晰

审计关心的是：

“什么时候跑的？失败了没有？有没有被跳过？”

你的设计里：

每次 ingestion 都是一个 DAG run

有：

execution_date

retry

failure callback

SLA

👉 对应 APRA CPS 230（Operational Risk）
系统失败 = 可见、可告警、可解释

2️⃣ dbt：把“业务逻辑”变成“审计资产”

审计不信：

Notebook

临时 SQL

人工口径

审计信：

Git

版本

文档

测试

你的 dbt 设计提供：

版本化业务规则

模型血缘

字段级定义

数据质量测试

👉 对应 CPS 235（数据风险管理）
数据准确性 ≠ 人工保证，而是系统保证

四、为什么分层（Bronze / Silver / Gold / Semantic）是“合规结构”，不是工程洁癖
审计的核心担忧

“原始数据被改了怎么办？”

你的分层回答

Bronze：原始、不可变、只追加

Silver：清洗与标准化（仍可追溯）

Gold：对外“事实来源”

Semantic：指标视图，不回写历史

为什么能过审

原始事实永远保留

每一层职责单一

出问题可以：

回到上游

重算下游

对比差异

👉 审计结论：“数据演进路径清晰，不可逆操作受控”

五、为什么 Snowflake RBAC + Masking 是“监管默认解法”
审计最怕的一句话

“我们信任 analyst 不乱看数据”

这是绝对不过审的。

你的设计

RBAC

工程 / 分析 / BI 服务账号分离

Masking Policy

PII 默认脱敏

Row Access Policy

按业务线 / 产品隔离

Access History

谁看了什么，一查就有

对应法规

Privacy Act（访问最小化）

CPS 234（访问控制与审计）

👉 审计结论：“不是靠人自觉，而是系统强制”

六、为什么 batch_id / rule_version 是“审计杀手锏”
审计一定会问：

“这个数字 12 个月前是怎么算出来的？”

你的架构能回答：

哪个原始文件（file hash）

哪次运行（batch_id）

哪套规则（dbt model version）

哪个时间点（execution_date）

👉 满足：

ASIC 报表可解释性

APRA 数据可重现性

这是很多平台过不了审的致命点，而你是提前设计进去的。

七、为什么“不是把逻辑都推到 BI / Semantic”反而更合规
审计的恐惧

“同一份数据，不同人算出不同结果”

你的原则：

Gold 层：

改变粒度

归并事实

固化规则（版本化）

Semantic 层：

只做可解释、可复用的指标

不破坏历史事实

👉 结果：

历史报表稳定

动态分析有边界

规则变更可审计

八、你可以用的“过审总结句”（非常重要）

你可以在二面最后说这一段：

This architecture passes audit not because of any single tool, but because it embeds regulatory expectations directly into the data lifecycle.

Encryption, access control, lineage, and reproducibility are not bolt-ons — they’re default behaviours of the platform.

That’s what allows us to scale data usage without increasing regulatory risk.

九、如果审计/面试官继续追问（准备好的三连答）
Q1：如果密钥泄露怎么办？

👉 Key rotation + access logs + limited blast radius（临时明文、短 TTL）

Q2：如果 dbt 规则错了，已经出报表了？

👉 规则版本 + 影响范围可定位 + 可重算并解释差异

Q3：如果 analyst 越权访问了 PII？

👉 Masking 默认开启 + access history + incident response 流程

最终一句话（你心里要有）

这套设计能过审，是因为它把“工程确定性”转化成了“监管确定性”。

因为文件大小只是“显性约束”，真正把方案推向 A / B / C 的，往往是一组隐含条件。

我给你一个**“隐含条件雷达图”：
👉 每一条，都是面试官心里默认存在、但不会写在题目里的前提**。
👉 真正健壮的方案，是对这些条件都有答案。

一、最关键的隐含条件总览（先给全景）

除了「文件大小」，通常还隐含着 7 大类条件：

数据敏感性 & 法规级别

数据一致性与“事实权威”

幂等性与重复投递

时间语义（什么时候算“正确”）

失败模式 & 可恢复性

组织与人（谁在用、谁会犯错）

未来演进路径（而不是当前需求）

下面我一条条拆，并且告诉你：
👉 每一条会怎样“反向约束”你的架构设计

二、隐含条件 1：数据“到底有多敏感”（不是一句 PII 就完）
隐含问题

这些数据 是否允许在任何时刻以明文形式存在？
是否允许工程师看到？是否允许被缓存？是否允许被 BI 直接查？

影响架构的地方

解密 发生在哪里

明文 是否能落盘

Gold / Semantic 是否能包含字段

架构推论

❌ 不能把解密写在随便一段 Python 里

❌ 不能在 Bronze/Silver 随意展开 PII

✅ 必须有：

受控解密区

Masking / Tokenisation

默认最小暴露

👉 这是 Privacy Act / CPS 234 的隐含前提

三、隐含条件 2：什么是“事实的唯一真源”（Source of Truth）
隐含问题

如果业务、合规、审计同时问：
“这个数字哪个是准的？”

影响架构的地方

Gold 层是不是唯一权威

Semantic 层能不能“随便算”

BI 里允不允许复杂逻辑

架构推论

❌ 不能把“改变事实”的逻辑放 BI

❌ 不能允许 analyst 各算各的

✅ Gold 层必须是：

可解释

版本化

可重现

👉 这是 ASIC / 审计隐含条件

四、隐含条件 3：文件“会不会重复来 / 乱序来”

这条非常关键，但题目几乎从不写

隐含问题

文件可能：

重复投递

延迟投递

顺序错误

同一天多个版本？

影响架构的地方

是否支持幂等

是否有 file_hash / batch_id

COPY / MERGE 语义

架构推论

❌ “看到文件就 load” 是不够的

❌ 不能只靠文件名

✅ 必须：

内容 hash

批次控制表

去重策略

👉 这是“生产事故”隐含条件

五、隐含条件 4：时间语义（Event Time vs Process Time）
隐含问题

“数据什么时候才算‘生效’？”

是文件落地时间？

是业务事件时间？

是入库时间？

影响架构的地方

增量逻辑

回算（backfill）

报表口径

架构推论

❌ 不能只用 ingestion_time

❌ 不能混用时间口径

✅ Silver / Gold 必须：

明确 event_time

保存 process_time

明确 late-arriving data 处理策略

👉 这是数据正确性 & 历史一致性的隐含条件

六、隐含条件 5：失败“是异常，还是常态”
隐含问题

如果失败：

是人工重跑？

是自动恢复？

是部分成功？

影响架构的地方

是否支持断点续跑

是否有 quarantine

是否能精确重算

架构推论

❌ “全跑一遍”在生产不可接受

❌ 无法定位失败记录 = 不可控

✅ 必须：

raw 数据不可变

silver/gold 可重算

失败可隔离

👉 这是 CPS 230（Operational Risk）的隐含要求

七、隐含条件 6：谁在用系统（以及他们一定会犯的错）
隐含问题

Analyst 会不会：

误 join

误过滤

误暴露 PII？

新人能不能“安全使用”？

影响架构的地方

是否有 Semantic 层

是否强制指标定义

是否默认 masking

架构推论

❌ 把所有权力给 BI 用户 = 高风险

❌ 让人“自觉合规”= 审计不过

✅ 系统必须：

默认安全

最小权限

错了也不至于出大事

👉 这是“人是系统最不可靠部分”的隐含条件

八、隐含条件 7：6–18 个月后会发生什么
隐含问题

数据量会不会翻倍？

新业务线会不会进来？

规则会不会被监管改？

影响架构的地方

是否模块化

是否支持版本并存

是否能演进而非推倒重来

架构推论

❌ 为“当前文件”定制 pipeline

❌ hardcode 业务规则

✅ 平台化思维：

模板

约定

数据产品

👉 这是 Senior / Lead 的隐含考察点

九、你可以在面试中这样“点破隐含条件”（非常加分）

你可以说类似这段话：

Beyond file size, the design is really driven by a set of implicit constraints — data sensitivity, idempotency, time semantics, failure recovery, and auditability.

If those aren’t addressed upfront, the pipeline may work technically but will fail under compliance review or real operational pressure.

这句话面试官一听就知道你是“踩过坑的人”。

十、一句终极总结（你心里要有）

文件大小决定“能不能跑”，
隐含条件决定“敢不敢上生产、能不能过审”。

主图：端到端（Blob 加密 Parquet → 受控解密 → Snowflake raw → dbt（Silver/Gold/Semantic）→ BI）

侧图：把你说的那些“隐含条件”作为**控制平面（Control Plane）**挂在关键节点上（幂等、时间语义、失败隔离、审计、权限、密钥、回放）。

你可以只画主图，也可以在二面说：“旁边这部分是我认为题目隐含但决定是否能上生产的约束条件。”

1) End-to-End Pipeline（含安全/治理控制点）
flowchart LR
  %% =========================
  %% DATA PLANE (end-to-end)
  %% =========================
  subgraph Azure["Azure Data Plane"]
    BLOB[(Azure Blob Storage\nlanding/encrypted/*.parquet.enc)]
    KV[(Azure Key Vault\nCMK + Secrets)]
    AF[Airflow (on AKS/VM)\nDAG Orchestration]
    CMP[Secure Compute Boundary\nDatabricks Job / AKS Job]
    QZ[(Quarantine Zone\nbad files/records)]
    DZ[(Decrypted Short-Lived Zone\nraw/decrypted/ TTL)]
  end

  subgraph Snowflake["Snowflake Data Platform"]
    STG[(External/Internal Stage)]
    RAW[(RAW schema\nimmutable loads)]
    SIL[(SILVER schema\nstaging/standardised)]
    GOLD[(GOLD schema\nfacts/dims/data products)]
    SEM[(SEMANTIC schema\nmetrics/views)]
    BI[BI Layer\nPower BI / Tableau]
  end

  %% Main flow
  BLOB -->|1 File lands| AF
  AF -->|2 Validate name + checksum| AF
  AF -->|3 Fetch key handle (no plaintext keys)| KV
  AF -->|4 Trigger decrypt job| CMP
  CMP -->|5 Read encrypted| BLOB
  CMP -->|6 Decrypt in memory/temp\n(no long-lived plaintext)| DZ
  CMP -->|7 On decrypt/parse failure| QZ
  AF -->|8 COPY INTO / load| STG
  DZ -->|9 Stage reference| STG
  STG -->|10 COPY INTO raw| RAW

  RAW -->|11 dbt: stg/int| SIL
  SIL -->|12 dbt: marts| GOLD
  GOLD -->|13 semantic models| SEM
  SEM -->|14 governed consumption| BI

  %% Optional backfeed for issue handling
  SIL -->|DQ failures route| QZ

2) Control Plane（把“隐含条件”挂到图上）
flowchart TB
  %% =========================
  %% CONTROL PLANE (implicit constraints)
  %% =========================

  subgraph Controls["Implicit Conditions / Control Plane (Audit-Ready)"]
    C1["Data Sensitivity & Exposure\n- PII classification\n- Default masking\n- Least privilege"]
    C2["Idempotency & Duplicates\n- file_hash + batch_id\n- control table\n- dedupe strategy"]
    C3["Time Semantics\n- event_time vs ingest_time\n- late arrivals\n- backfill policy"]
    C4["Failure Modes & Recovery\n- quarantine\n- retries\n- replay by batch_id"]
    C5["Auditability & Reproducibility\n- lineage (dbt artifacts)\n- versioned logic\n- run_id traceability"]
    C6["Key & Secret Management\n- Key Vault\n- rotation\n- no secrets in DAG"]
    C7["Access & Governance\n- Snowflake RBAC\n- masking/row policies\n- access history"]
    C8["Change & Evolution\n- schema contracts\n- on_schema_change\n- deprecation/versioning"]
    C9["Operational Observability\n- SLA/alerts\n- row counts\n- freshness tests\n- cost/credits monitoring"]
  end

  %% Attach controls to pipeline stages (conceptual links)
  C6 -->|"applies to"| KVA["Key Vault usage"]
  C1 -->|"applies to"| PII["PII handling points\n(SIL/GOLD/SEM/BI)"]
  C2 -->|"applies to"| IDEMP["Ingestion control\n(AF + RAW)"]
  C3 -->|"applies to"| TIME["Silver/Gold modeling"]
  C4 -->|"applies to"| REC["Quarantine + Replay"]
  C5 -->|"applies to"| AUD["dbt + Airflow run metadata"]
  C7 -->|"applies to"| RBAC["Snowflake roles/policies"]
  C8 -->|"applies to"| SCHEMA["Schema evolution\n(raw→stg)"]
  C9 -->|"applies to"| OBS["Monitoring\n(AF/Snowflake/Azure)"]

3) 你在白板走读时的“挂钩讲法”（30 秒）

你可以这样讲（非常顺）：

数据面：Airflow 发现文件 → 受控计算环境解密 → Stage/COPY 进 RAW → dbt 分层到 Silver/Gold/Semantic → BI

控制面：真正决定能否上生产/过审的是这 9 个隐含条件：

PII 最小暴露、幂等、时间语义、失败隔离、审计可追溯、密钥管理、RBAC、schema 演进、可观测性

每一条都落在图里的具体节点（Key Vault、RAW/Silver/Gold、Quarantine、Airflow run metadata、Snowflake policies 等）