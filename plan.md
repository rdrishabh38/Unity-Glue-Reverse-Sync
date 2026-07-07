# plan.md: Local Lakehouse Interoperability POC (Delta UniForm to AWS Glue)

*Note: This is a high-level architectural plan. No code generation is required at this stage.*

## 1. Executive Summary & Problem Statement
**Problem:** In the organization's production environment, the central data catalog is hosted in AWS Glue. Consumers in Databricks read this data via a federated, read-only Glue data catalog. After manipulating the data, they write the results back as a new table in Unity Catalog. This new Unity Catalog table must then be **reverse-synced** back to the central AWS Glue catalog so that native AWS consumers (Athena/Redshift) can query the updated data without relying on Databricks compute or duplicating data.

**Solution:** Implement an end-to-end pipeline simulating this flow. Because AWS Glue Catalog API cannot be emulated locally without a paid license, we will use an **Open-Source Iceberg REST Catalog** to act as the "mock" central Glue catalog. We will originate data in this central catalog, perform a federated read into Spark (simulating Databricks), write the transformed data into Unity Catalog using Delta Lake's Universal Format (UniForm) to asynchronously generate Apache Iceberg metadata, and finally reverse-sync this metadata back to the central catalog.

**Objective:** Build a fully containerized, local Proof of Concept (POC) using LocalStack (for S3), an Iceberg REST Catalog (mocking Glue), open-source Unity Catalog, and open-source Apache Spark (Jupyter) to validate this complex, multi-directional architectural pattern before cloud deployment.

---

## 2. Infrastructure & Environment Architecture
The environment will consist of a multi-container Docker setup running locally.

* **Service 1: Cloud Storage Emulator (LocalStack)**
    * **Purpose:** Emulate AWS S3 (physical storage).
    * **Exposed Ports:** 4566.
    * **Required Services:** `s3`.

* **Service 2: Central Catalog Emulator (Iceberg REST)**
    * **Purpose:** Act as the local stand-in for the AWS Glue Data Catalog.
    * **Base:** `tabulario/iceberg-rest-image`
    * **Exposed Ports:** 8181.

* **Service 3: Compute Engine (Spark/Jupyter)**
    * **Purpose:** Simulate the Databricks environment and AWS Athena read environment. Jupyter provides an interactive, step-by-step visual demonstration for stakeholders.
    * **Base:** A standard Jupyter/PySpark image (Spark 3.5.0+).
    * **Exposed Ports:** 8888.

* **Service 4: Unity Catalog (OSS)**
    * **Purpose:** Act as the central governance layer for the Databricks side of the architecture. The web UI (port 3000) provides stakeholders with tangible proof of the catalog before diving into synchronization.
    * **Base:** Official pre-built Unity Catalog image (`unitycatalog/unitycatalog:latest`).
    * **Exposed Ports:** 8080 (API), 3000 (UI).

### Component Endpoints
* **Spark Jupyter Notebook (UI):** [http://localhost:8888](http://localhost:8888) (Primary workspace for pipeline execution)
* **Unity Catalog (UI):** [http://localhost:3000](http://localhost:3000) (Visual governance and table inspection)
* **Unity Catalog (API):** `http://localhost:8080`
* **Iceberg REST Catalog (API):** `http://localhost:8181`
* **LocalStack S3 (API):** `http://localhost:4566`

---

## 3. Implementation Phases

### Phase 1: Infrastructure Provisioning & Initialization
1.  **Docker Compose Definition:** Define the four services (`localstack`, `iceberg-rest`, `spark-jupyter`, and `unity-catalog`) with proper networking.
2.  **Storage Initialization:** Define a setup script (`init.sh`) to automatically create a mock S3 bucket (`s3://lakehouse-bucket`) in LocalStack.

### Phase 2: The Enterprise Data Pipeline (Read, Manipulate, Write)
**Goal:** Accurately simulate the production flow from the central catalog, through Databricks, and into Unity Catalog.
1.  **Phase 2A: Originate Central Data (Mock Glue):** Initialize a Spark session configured for the Iceberg REST Catalog. Create a mock "source" table directly in this central catalog and insert dummy data.
2.  **Phase 2B: Unity Catalog Federation Setup:** Configure Unity Catalog to create a federated connection pointing to the central catalog.
3.  **Phase 2C: Federated Read & Manipulation (Databricks Simulator):** In Spark, query the source table *via* Unity Catalog. Perform a data transformation on the dummy data.
4.  **Phase 2D: Write to Unity Catalog (Standard Delta):** Write the transformed DataFrame into Unity Catalog as a new table using the standard `delta` format and register it using the Unity Catalog REST API (bypassing OSS Spark integration bugs).

### Phase 3: The Reverse Sync to Central Catalog
**Goal:** Synchronize the newly created Unity Catalog table back to the central catalog bypassing broken OSS Delta converters.
1.  **Iceberg Table Creation:** Construct an empty Iceberg table in the Central Catalog (Iceberg REST) with a schema dynamically inferred from the raw Delta Parquet files.
2.  **Parquet File Adoption (Reverse Sync):** Using the Iceberg `add_files` stored procedure, adopt the raw Parquet data files directly into the Iceberg table manifest. This securely bridges the Unity Catalog data into the central catalog without duplicating physical files.

### Phase 4: The AWS Consumer Simulator (Validation)
**Goal:** Prove the reverse-synced data is readable from the central catalog.
1.  **Query Execution:** Execute a standard `SELECT * FROM` query targeting the newly reverse-synced table in the central catalog.
2.  **Assertion:** The query should output the transformed mock data, confirming that UniForm metadata successfully bridged the Delta-to-Iceberg gap.

### Phase 5 & 6: CRUD Operations & Edge Cases
*(Unchanged: Validate Create, Read, Update, Drop operations, IAM, KMS, and Vacuum behaviors across the bridged catalogs).*

---

## 4. Success Criteria
* The `docker-compose` environment spins up cleanly (LocalStack, Iceberg REST, Spark, Unity Catalog).
* The central "source" table is successfully created and readable via a federated connection.
* The transformed data is written to S3 and explicitly registered in Unity Catalog.
* The reverse sync procedure successfully adopts the physical Parquet files into the central catalog using Iceberg's native procedures.
* The final consumer query successfully retrieves the transformed data.
