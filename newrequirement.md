Scenario-Based Question: Data Engineering
Architecture Design
Context
You are joining a small data engineering team responsible for building secure, scalable pipelines
to support analytics and reporting across the business. Your first task is to design a production-
ready data pipeline that ingests encrypted data into Snowflake.
Input
 The source data is an encrypted Parquet file dropped into Azure Blob Storage.
 The file contains sensitive customer data and must be handled securely and in
compliance with data governance standards.
 Airflow will include a file watcher operator to detect when the file lands in Blob Storage.
You do not need to design any event grid or trigger logic.
Objective
Design a pipeline that:
1. Ingests the encrypted Parquet file from Azure Blob Storage.
2. Decrypts and transforms the data using dbt.
3. Loads the data into Snowflake for analytics and reporting.
4. Is orchestrated using Airflow.
5. Implements robust security controls and data governance.

What to Prepare
Please prepare a response that addresses the following:
1. Architecture Design
 What does the end-to-end pipeline look like?
 Which services and tools are used at each stage?
 How are components integrated (e.g. Azure Function, Airflow DAG, dbt models)?
2. Lakehouse Architecture &amp; Dimensional Modelling
 Describe a real-world pipeline that moves raw JSON logs from Bronze to a dimensional
model in Gold. What steps are required?
 What is the difference between Lakehouse architecture and a modern cloud data
warehouse?

 How do Medallion Architecture and Dimensional Modelling complement each other?
Where do they overlap?
 If our Lakehouse architecture is: Bronze → Silver → Gold → Semantic → BI Layer, when
should you not push business logic into the Semantic Layer and instead implement it in
Gold? What types of transformations must stay in Gold, what must move into Semantic,
and what must never be in either? Why
 If our BI dashboards require both historical accuracy and real-time adjustments (e.g.,
dynamic attribution windows), how would you architect this logic across Silver, Gold, and
Semantic?
3. Security and Governance
 How is data secured in transit and at rest?
 How is access managed between systems (e.g. Azure to Snowflake)?
 What does the Snowflake RBAC model look like (roles, privileges, masking, etc.)?
4. Operational Considerations
 How would you monitor, test, and deploy this pipeline?
 How would you handle schema changes, data quality issues, or failures?

Guidelines
 You are encouraged to ask clarifying questions if anything is unclear.
 You may use any tools, diagrams, or formats you prefer to communicate your design.
 A whiteboard will be available during the second interview if you prefer to draw or sketch
your architecture.