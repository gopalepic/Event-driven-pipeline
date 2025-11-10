# 🏗️ Project Architecture Deep Dive

## Event-Driven Data Pipeline Architecture

This document provides a comprehensive technical architecture overview of the Event-Driven Pipeline project.

---

## 📐 Architecture Diagram (Text-Based)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         AZURE CLOUD PLATFORM                            │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐    │
│  │                    USER / DATA SOURCE                          │    │
│  └────────────────────────┬──────────────────────────────────────┘    │
│                           │                                             │
│                           │ Upload JSON File                            │
│                           ▼                                             │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │         AZURE BLOB STORAGE (Data Container)                     │   │
│  │  - Stores JSON files                                           │   │
│  │  - Triggers events on upload                                    │   │
│  │  - LRS replication                                             │   │
│  └────────────────────┬───────────────────────────────────────────┘   │
│                       │                                                 │
│                       │ Blob Created Event                              │
│                       │                                                 │
│                       ▼                                                 │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │         AZURE FUNCTIONS (Serverless Compute)                    │   │
│  │                                                                 │   │
│  │  ┌──────────────────────────────────────────────────┐          │   │
│  │  │  ProcessBlob Function (TypeScript)               │          │   │
│  │  │  - Blob Trigger: data/{name}                     │          │   │
│  │  │  - Parses JSON (single object or array)          │          │   │
│  │  │  - Validates data structure                      │          │   │
│  │  │  - Handles errors with logging                   │          │   │
│  │  └──────────────────┬───────────────────────────────┘          │   │
│  │                     │                                           │   │
│  └─────────────────────┼───────────────────────────────────────────┘   │
│                        │                                                │
│                        │ Upsert Data                                    │
│                        │                                                │
│                        ▼                                                │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │         AZURE COSMOS DB (NoSQL Database)                        │   │
│  │                                                                 │   │
│  │  Database: pipeline-db                                         │   │
│  │  Container: data                                               │   │
│  │  Partition Key: /id                                            │   │
│  │  Consistency: Session                                          │   │
│  │  - Stores processed JSON documents                             │   │
│  │  - Supports global distribution                                │   │
│  │  - Low latency reads/writes                                    │   │
│  └────────────────────┬───────────────────────────────────────────┘   │
│                       │                                                 │
│                       │ Daily Extract                                   │
│                       │                                                 │
│                       ▼                                                 │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │         AZURE DATA FACTORY (ETL/Orchestration)                  │   │
│  │                                                                 │   │
│  │  Pipeline: DailyReportPipeline                                 │   │
│  │  - Schedule: Daily trigger                                     │   │
│  │  - Extract: Cosmos DB → CSV                                    │   │
│  │  - Transform: JSON to Delimited Text                           │   │
│  │  - Load: Save to Blob Storage                                  │   │
│  └────────────────────┬───────────────────────────────────────────┘   │
│                       │                                                 │
│                       │ Save Report                                     │
│                       ▼                                                 │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │         AZURE BLOB STORAGE (Reports Container)                  │   │
│  │  - Daily CSV reports                                           │   │
│  │  - Analytics data export                                       │   │
│  └────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE & DEVOPS LAYER                        │
│                                                                         │
│  ┌──────────────────┐      ┌──────────────────┐      ┌──────────────┐ │
│  │   TERRAFORM      │      │  GITHUB ACTIONS  │      │ AZURE DEVOPS │ │
│  │   (IaC)          │      │  (CI/CD)         │      │ (CI/CD)      │ │
│  │                  │      │                  │      │              │ │
│  │ - Resource Group │      │ - Build          │      │ - Build      │ │
│  │ - Storage Acct   │      │ - Test           │      │ - Deploy     │ │
│  │ - Function App   │      │ - Deploy         │      │ - ADF Deploy │ │
│  │ - Cosmos DB      │      │                  │      │              │ │
│  │ - Data Factory   │      │                  │      │              │ │
│  └──────────────────┘      └──────────────────┘      └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Data Flow Sequence

### Real-Time Event Processing Flow

```
1. FILE UPLOAD
   └─> User/System uploads JSON file to Blob Storage "data" container
       Example: sales-data-2024-01-15.json

2. EVENT TRIGGER
   └─> Blob Storage emits "blob created" event
       └─> Azure Functions runtime detects the event
           └─> Instantiates function (cold start if needed)

3. FUNCTION EXECUTION
   └─> ProcessBlob.ts handler invoked
       ├─> Receives blob content as Buffer
       ├─> Converts to string: blob.toString()
       ├─> Parses JSON: JSON.parse(blobString)
       ├─> Determines if single object or array
       └─> Normalizes to array format

4. DATA VALIDATION
   └─> For each item in array:
       ├─> Validates required fields (id must exist)
       ├─> Logs item ID
       └─> Prepares for database write

5. DATABASE WRITE
   └─> Connects to Cosmos DB using CosmosClient
       ├─> Endpoint: process.env.COSMOSDB_ENDPOINT
       ├─> Auth: process.env.COSMOSDB_KEY
       └─> Database: "pipeline-db"
           └─> Container: "data"
               └─> For each item:
                   ├─> container.items.upsert(item)
                   ├─> Partition key: item.id
                   └─> Returns: Item metadata

6. COMPLETION
   └─> Logs success message with count
   └─> Function completes
   └─> Resources released (serverless)

7. DAILY REPORTING (Parallel Process)
   └─> Daily trigger fires
       └─> Azure Data Factory pipeline starts
           ├─> Connects to Cosmos DB
           ├─> Queries all documents from "data" container
           ├─> Transforms to CSV format
           └─> Writes to Blob Storage reports container
```

---

## 🏛️ Azure Resources Architecture

### Resource Hierarchy

```
Azure Subscription
└─> Resource Group: event-pipeline-rg
    ├─> Storage Account: mypipelinedata{random}
    │   ├─> Blob Container: data (for input files)
    │   └─> Blob Container: reports (for output files)
    │
    ├─> Cosmos DB Account: mypipeline-cosmos-{random}
    │   └─> Database: pipeline-db
    │       └─> Container: data
    │           ├─> Partition Key: /id
    │           ├─> Throughput: Auto-scale RU/s
    │           └─> Consistency: Session
    │
    ├─> App Service Plan: pipeline-plan
    │   ├─> Type: Linux
    │   ├─> SKU: Y1 (Consumption)
    │   └─> Serverless: Yes
    │
    ├─> Function App: pipeline-function-{random}
    │   ├─> Runtime: Node.js 18
    │   ├─> Language: TypeScript
    │   ├─> Functions:
    │   │   └─> blobTrigger (ProcessBlob)
    │   └─> App Settings:
    │       ├─> AzureWebJobsStorage
    │       ├─> COSMOSDB_ENDPOINT
    │       ├─> COSMOSDB_KEY
    │       └─> FUNCTIONS_WORKER_RUNTIME=node
    │
    └─> Data Factory: pipeline-adf-{random}
        └─> Pipelines:
            └─> DailyReportPipeline
                ├─> Source: CosmosDB
                ├─> Sink: Blob Storage (CSV)
                └─> Trigger: Daily schedule
```

---

## 🔐 Security Architecture

### Authentication & Authorization Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     SECURITY LAYERS                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. NETWORK SECURITY                                            │
│     ├─> HTTPS only for all communications                      │
│     ├─> Private blob containers (no anonymous access)          │
│     └─> Firewall rules (can be configured)                     │
│                                                                 │
│  2. AUTHENTICATION                                              │
│     ├─> Function App ─[Connection String]─> Storage            │
│     ├─> Function App ─[Primary Key]─> Cosmos DB                │
│     └─> (Future: Managed Identity for passwordless auth)       │
│                                                                 │
│  3. SECRETS MANAGEMENT                                          │
│     ├─> Environment Variables (current)                        │
│     │   ├─> AzureWebJobsStorage                                │
│     │   ├─> COSMOSDB_ENDPOINT                                  │
│     │   └─> COSMOSDB_KEY                                       │
│     └─> Azure Key Vault (production recommendation)            │
│                                                                 │
│  4. ACCESS CONTROL                                              │
│     ├─> Azure RBAC for resource management                     │
│     ├─> Storage Account Keys (currently used)                  │
│     ├─> Cosmos DB Keys (currently used)                        │
│     └─> Managed Identity (recommended for production)          │
│                                                                 │
│  5. DATA SECURITY                                               │
│     ├─> Encryption at rest (automatic in Azure)                │
│     ├─> Encryption in transit (TLS 1.2+)                       │
│     └─> Geo-redundancy option (configurable)                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 CI/CD Architecture

### GitHub Actions Pipeline

```
┌────────────────────────────────────────────────────────────┐
│              GITHUB ACTIONS WORKFLOW                       │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  TRIGGER: Push to 'main' or Pull Request                  │
│     │                                                      │
│     ├─> Job: build-and-deploy (ubuntu-latest)             │
│     │                                                      │
│     ├─> Step 1: Checkout code                             │
│     │   └─> actions/checkout@v4                           │
│     │                                                      │
│     ├─> Step 2: Setup Node.js 18                          │
│     │   └─> actions/setup-node@v4                         │
│     │                                                      │
│     ├─> Step 3: Install dependencies                      │
│     │   └─> cd process_data && npm install                │
│     │                                                      │
│     ├─> Step 4: Build TypeScript                          │
│     │   └─> npm run build (tsc compilation)               │
│     │   └─> Output: dist/ directory with JS files         │
│     │                                                      │
│     ├─> Step 5: Create deployment package                 │
│     │   └─> zip -r function-app.zip                       │
│     │   └─> Excludes: .git, node_modules/.cache           │
│     │                                                      │
│     └─> Step 6: Deploy to Azure Functions                 │
│         └─> Azure/functions-action@v1                     │
│         └─> Using: AZURE_FUNCTIONAPP_PUBLISH_PROFILE      │
│         └─> Target: process-data-dxjhc2i0                 │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Azure DevOps Pipeline

```
┌────────────────────────────────────────────────────────────┐
│            AZURE DEVOPS PIPELINE                           │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  TRIGGER: Push to 'main' branch                           │
│                                                            │
│  ┌────────────────────────────────────────────────────┐   │
│  │  STAGE 1: BuildAndDeployFunction                   │   │
│  ├────────────────────────────────────────────────────┤   │
│  │                                                    │   │
│  │  Job 1: BuildFunction                             │   │
│  │    ├─> Install Node.js 18                         │   │
│  │    ├─> npm install && npm run build               │   │
│  │    ├─> Archive to ZIP                             │   │
│  │    └─> Publish artifact: function-app             │   │
│  │                                                    │   │
│  │  Job 2: DeployFunction (depends on BuildFunction) │   │
│  │    ├─> Download artifact: function-app            │   │
│  │    └─> Deploy to Azure Function App               │   │
│  │       └─> Service: Azure for Studentes            │   │
│  │       └─> App: process-data-dxjhc2i0               │   │
│  └────────────────────────────────────────────────────┘   │
│                                                            │
│  ┌────────────────────────────────────────────────────┐   │
│  │  STAGE 2: DeployADF                               │   │
│  ├────────────────────────────────────────────────────┤   │
│  │                                                    │   │
│  │  Job: DeployDataFactory                           │   │
│  │    └─> Deploy ADF Pipeline using Azure CLI        │   │
│  │       └─> Factory: pipeline-adf-dxjhc2i0           │   │
│  │       └─> Pipeline: DailyReportPipeline            │   │
│  └────────────────────────────────────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## 📊 Scalability Architecture

### Horizontal Scaling Capabilities

```
┌────────────────────────────────────────────────────────────────┐
│                    SCALABILITY MODEL                           │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  Azure Functions (Compute)                                     │
│  ├─> Consumption Plan                                          │
│  │   ├─> Auto-scale: 0 to 200 instances                       │
│  │   ├─> Triggered by queue depth                             │
│  │   ├─> Scale-out time: ~30 seconds                          │
│  │   └─> Cost: Pay per execution + GB-seconds                 │
│  │                                                             │
│  └─> Concurrency                                               │
│      ├─> Each instance handles 1 blob at a time               │
│      ├─> Multiple instances run in parallel                   │
│      └─> Total throughput: ~200 blobs/minute (theoretical)    │
│                                                                │
│  Cosmos DB (Database)                                          │
│  ├─> Provisioned Throughput (RU/s)                            │
│  │   ├─> Can scale from 400 to 1,000,000+ RU/s               │
│  │   ├─> Auto-scale enabled                                   │
│  │   └─> Partitioned by /id for horizontal scaling           │
│  │                                                             │
│  └─> Global Distribution (if enabled)                         │
│      ├─> Multi-region writes                                  │
│      ├─> Low latency worldwide                                │
│      └─> Automatic failover                                   │
│                                                                │
│  Blob Storage (Event Source)                                   │
│  ├─> Virtually unlimited storage                              │
│  ├─> High throughput (thousands of operations/second)         │
│  └─> Geo-redundancy options available                         │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Performance Characteristics

| Component | Latency | Throughput | Scalability |
|-----------|---------|------------|-------------|
| Blob Upload | < 1s | Unlimited | Automatic |
| Function Trigger | 1-5s | 200 concurrent | Auto-scale |
| Cosmos DB Write | < 10ms | Based on RU/s | Manual/Auto |
| End-to-End | 2-10s | ~200 files/min | Horizontal |

---

## 💰 Cost Architecture

### Estimated Monthly Costs (Moderate Usage)

```
┌──────────────────────────────────────────────────────────┐
│              COST BREAKDOWN (USD/month)                  │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Azure Functions (Consumption Plan)                     │
│  ├─> Executions: 100,000/month                         │
│  ├─> Duration: 1s average per execution                │
│  ├─> Memory: 512 MB                                    │
│  └─> Cost: ~$1-2/month                                 │
│      (First 1M executions + 400K GB-s free)            │
│                                                          │
│  Azure Blob Storage                                     │
│  ├─> Storage: 10 GB data                               │
│  ├─> Operations: 100,000 write, 50,000 read            │
│  └─> Cost: ~$2-3/month                                 │
│                                                          │
│  Azure Cosmos DB                                        │
│  ├─> Throughput: 400 RU/s (auto-scale)                │
│  ├─> Storage: 5 GB                                     │
│  └─> Cost: ~$25-30/month                               │
│      (Largest cost component)                          │
│                                                          │
│  Azure Data Factory                                     │
│  ├─> Pipeline runs: 30/month (daily)                  │
│  ├─> Activity runs: 30                                │
│  └─> Cost: ~$1-2/month                                 │
│                                                          │
│  ──────────────────────────────────────────────        │
│  TOTAL ESTIMATED: $30-40/month                         │
│                                                          │
│  Comparison:                                            │
│  VM-based solution: $200+/month                        │
│  Savings: ~80%                                         │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### Cost Optimization Strategies

1. **Serverless Architecture**: Pay only when processing files
2. **Auto-scaling**: Scale to zero when idle
3. **Appropriate storage tier**: Standard LRS for cost efficiency
4. **Session consistency**: Lower cost than Strong consistency
5. **Reserved capacity**: Can purchase for predictable workloads

---

## 🔍 Monitoring & Observability Architecture

### Logging & Monitoring Stack

```
┌────────────────────────────────────────────────────────────┐
│                  MONITORING LAYERS                         │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  1. APPLICATION INSIGHTS (Function Monitoring)             │
│     ├─> Request tracking                                  │
│     ├─> Dependency calls (Cosmos DB)                      │
│     ├─> Exception tracking                                │
│     ├─> Performance metrics                               │
│     ├─> Custom events and metrics                         │
│     └─> Live metrics stream                               │
│                                                            │
│  2. AZURE MONITOR (Resource Metrics)                       │
│     ├─> Function execution count                          │
│     ├─> Function execution time                           │
│     ├─> Function failures                                 │
│     ├─> Cosmos DB RU consumption                          │
│     ├─> Storage account operations                        │
│     └─> Alert rules                                       │
│                                                            │
│  3. LOG ANALYTICS (Centralized Logging)                    │
│     ├─> Query logs with KQL                               │
│     ├─> Custom dashboards                                 │
│     ├─> Workbooks for analysis                            │
│     └─> Correlation across resources                      │
│                                                            │
│  4. FUNCTION LOGGING (Application Logs)                    │
│     ├─> context.log() statements                          │
│     ├─> Processing blob: {name}                           │
│     ├─> Saved item with id: {id}                          │
│     ├─> Data saved to Cosmos DB - {count} items           │
│     └─> Error messages with stack traces                  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Key Metrics to Monitor

| Metric | Threshold | Action |
|--------|-----------|--------|
| Function Failures | > 5% | Alert on-call |
| Function Duration | > 30s | Investigate performance |
| Cosmos DB RU/s | > 80% | Scale up throughput |
| Cosmos DB Throttling | > 0 | Increase RU/s or optimize queries |
| Storage Errors | > 1% | Check connectivity |
| Cold Start Time | > 5s | Consider Premium plan |

---

## 🔄 Disaster Recovery & High Availability

### Business Continuity Architecture

```
┌────────────────────────────────────────────────────────────┐
│           DISASTER RECOVERY STRATEGY                       │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  Infrastructure Recovery                                   │
│  └─> Terraform state stored in Azure Storage              │
│      └─> Can rebuild entire infrastructure in ~10 min     │
│      └─> terraform apply in new region                    │
│                                                            │
│  Data Recovery                                             │
│  ├─> Blob Storage: Geo-redundant storage option (GRS)     │
│  │   └─> Data replicated to paired region                │
│  │   └─> RPO: ~15 minutes                                │
│  │                                                         │
│  └─> Cosmos DB: Multi-region replication                  │
│      └─> Can configure automatic failover                 │
│      └─> RTO: < 1 minute for failover                     │
│      └─> RPO: Based on consistency level                  │
│                                                            │
│  Code Recovery                                             │
│  ├─> Source code in GitHub                                │
│  ├─> CI/CD pipelines redeploy automatically              │
│  └─> Function app packages in artifact storage            │
│                                                            │
│  Configuration Recovery                                    │
│  ├─> Terraform code includes all config                   │
│  ├─> Environment variables documented                     │
│  └─> Secrets can be retrieved from Key Vault             │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## 🧪 Testing Strategy Architecture

### Test Pyramid (Recommended)

```
                    ┌─────────────────┐
                    │   Manual Tests  │ (Interview demos)
                    │   End-to-End    │
                    └────────┬────────┘
                             │
                   ┌─────────┴────────┐
                   │ Integration Tests│ (Function + Cosmos)
                   │  (Recommended)   │
                   └────────┬─────────┘
                            │
              ┌─────────────┴─────────────┐
              │      Unit Tests           │
              │  (Test JSON parsing,      │
              │   data validation)        │
              └───────────────────────────┘
```

### Testing Approach

1. **Unit Tests** (to be added)
   - Test JSON parsing logic
   - Test array normalization
   - Test error handling

2. **Integration Tests** (to be added)
   - Test Function → Cosmos DB integration
   - Test with Azure Storage Emulator (Azurite)
   - Test error scenarios

3. **Manual Testing** (current approach)
   - Upload test JSON files
   - Verify logs in Function App
   - Query Cosmos DB for results
   - Validate CSV reports

---

## 🎯 Architecture Decisions & Trade-offs

### Key Decisions Made

| Decision | Alternative | Rationale |
|----------|------------|-----------|
| **Serverless Functions** | Container Apps, VMs | Event-driven workload, cost optimization |
| **Cosmos DB** | SQL Database | Flexible schema, global distribution, JSON native |
| **Blob Trigger** | Event Grid, Queue | Simpler setup, built-in retry logic |
| **TypeScript** | JavaScript | Type safety, better IDE support |
| **Consumption Plan** | Premium Plan | Cost-effective for sporadic loads |
| **Session Consistency** | Strong Consistency | Balance of performance and cost |
| **Partition Key: /id** | Custom partition | Even distribution, simple implementation |
| **Terraform** | ARM Templates, Portal | Multi-cloud skills, better dev experience |

### Trade-offs Accepted

| Trade-off | Impact | Mitigation |
|-----------|--------|------------|
| Cold starts | 1-5s initial latency | Can upgrade to Premium Plan if needed |
| No message queue | Limited retry control | Functions has built-in retry for blob triggers |
| Manual throughput | May need monitoring | Auto-scale enabled on Cosmos DB |
| Regional deployment | No multi-region HA | Terraform can deploy to multiple regions |

---

## 📚 Technology Deep Dive

### Azure Functions Runtime

```
┌────────────────────────────────────────────────────────────┐
│               FUNCTION APP RUNTIME                         │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  Runtime Stack                                             │
│  ├─> Node.js 18.x                                         │
│  ├─> Azure Functions Runtime v4                           │
│  └─> TypeScript compiler (tsc)                            │
│                                                            │
│  Binding Configuration                                     │
│  ├─> Trigger: storageBlob                                │
│  ├─> Path: data/{name}                                    │
│  ├─> Connection: AzureWebJobsStorage                      │
│  └─> Direction: in                                        │
│                                                            │
│  Execution Model                                           │
│  ├─> Event-driven invocation                              │
│  ├─> Stateless execution                                  │
│  ├─> Auto-retry on failure                                │
│  └─> Scaling based on queue depth                         │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Cosmos DB Data Model

```json
{
  "Database": "pipeline-db",
  "Container": "data",
  "PartitionKey": "/id",
  "IndexingPolicy": {
    "automatic": true,
    "indexingMode": "consistent"
  },
  "Document Structure": {
    "id": "unique-identifier (required)",
    "value": "any-data-field",
    "...": "flexible schema"
  }
}
```

---

## 🌐 Network Architecture

```
┌────────────────────────────────────────────────────────────┐
│                  NETWORK TOPOLOGY                          │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  Public Endpoints (HTTPS Only)                             │
│  ├─> Function App: pipeline-function-*.azurewebsites.net  │
│  ├─> Cosmos DB: *.documents.azure.com:443                 │
│  └─> Blob Storage: *.blob.core.windows.net                │
│                                                            │
│  Private Networking (Future Enhancement)                   │
│  ├─> Virtual Network integration                          │
│  ├─> Private endpoints for Cosmos DB                      │
│  ├─> Storage firewall rules                               │
│  └─> Network Security Groups                              │
│                                                            │
│  Traffic Flow                                              │
│  ├─> User → [HTTPS] → Blob Storage                        │
│  ├─> Blob Storage → [Event] → Functions                   │
│  ├─> Functions → [HTTPS + Auth] → Cosmos DB               │
│  └─> Data Factory → [HTTPS + Auth] → Cosmos DB, Storage   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## 🔧 Development Workflow

```
Developer Workflow
├─> 1. Local Development
│   ├─> Edit code in process_data/src/functions/
│   ├─> npm install (install dependencies)
│   ├─> npm run build (compile TypeScript)
│   └─> func start (test locally)
│
├─> 2. Testing
│   ├─> Start Azurite (local storage emulator)
│   ├─> Upload test files to local storage
│   └─> Verify function execution in terminal
│
├─> 3. Commit & Push
│   ├─> git add .
│   ├─> git commit -m "message"
│   └─> git push origin main
│
├─> 4. CI/CD Pipeline (Automatic)
│   ├─> GitHub Actions triggers
│   ├─> Builds code
│   ├─> Creates deployment package
│   └─> Deploys to Azure
│
└─> 5. Verification
    ├─> Check deployment logs
    ├─> Upload test file to Azure Storage
    ├─> Verify in Application Insights
    └─> Query Cosmos DB for results
```

---

## 📊 Data Model Examples

### Input (JSON Blob)

```json
// Single object
{
  "id": "order-12345",
  "customerName": "John Doe",
  "amount": 99.99,
  "timestamp": "2024-01-15T10:30:00Z"
}

// Or array of objects
[
  {
    "id": "sensor-001",
    "temperature": 72.5,
    "humidity": 45.2,
    "location": "warehouse-a"
  },
  {
    "id": "sensor-002",
    "temperature": 68.3,
    "humidity": 52.1,
    "location": "warehouse-b"
  }
]
```

### Storage (Cosmos DB)

```json
{
  "id": "order-12345",
  "customerName": "John Doe",
  "amount": 99.99,
  "timestamp": "2024-01-15T10:30:00Z",
  "_rid": "auto-generated-resource-id",
  "_self": "dbs/pipeline-db/colls/data/docs/order-12345/",
  "_etag": "auto-generated-etag",
  "_ts": 1705318200
}
```

### Output (CSV Report)

```csv
id,customerName,amount,timestamp
order-12345,John Doe,99.99,2024-01-15T10:30:00Z
order-12346,Jane Smith,149.99,2024-01-15T11:45:00Z
```

---

## 🎓 Learning Outcomes from This Architecture

### Cloud Architecture Patterns
- ✅ Event-driven architecture
- ✅ Serverless computing model
- ✅ Microservices principles
- ✅ PaaS service integration
- ✅ Data pipeline design

### Best Practices Applied
- ✅ Infrastructure as Code
- ✅ CI/CD automation
- ✅ Configuration management
- ✅ Logging and monitoring
- ✅ Security by design
- ✅ Cost optimization
- ✅ Scalability planning

### Azure Expertise
- ✅ Azure Functions (deep dive)
- ✅ Azure Blob Storage
- ✅ Azure Cosmos DB
- ✅ Azure Data Factory
- ✅ Azure Resource Manager
- ✅ Azure DevOps
- ✅ GitHub integration with Azure

---

**This architecture represents a production-ready, scalable, and cost-effective solution for event-driven data processing in the cloud.** 🚀
