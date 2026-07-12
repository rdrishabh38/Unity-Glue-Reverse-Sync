# Unity-Glue-Reverse-Sync

![License: GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Python](https://img.shields.io/badge/python-3.11-blue.svg)
![Spark](https://img.shields.io/badge/Spark-3.5.0-E25A1C?style=flat&logo=apachespark&logoColor=white)
![Delta Lake](https://img.shields.io/badge/Delta_Lake-3.2.0-00ADD8?style=flat&logo=databricks&logoColor=white)
![Apache Iceberg](https://img.shields.io/badge/Apache_Iceberg-1.5.0-00ADD8?style=flat&logo=apacheiceberg&logoColor=white)
![Unity Catalog](https://img.shields.io/badge/Unity_Catalog-OSS-FF3621?style=flat&logo=databricks&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)
![AWS Glue](https://img.shields.io/badge/AWS_Glue-LocalStack-232F3E?style=flat&logo=amazonwebservices&logoColor=white)

**Unity-Glue-Reverse-Sync** is a proof-of-concept Open Lakehouse Data Federation pipeline. It demonstrates how to achieve a "single copy of data" architecture by writing Delta Lake tables into Unity Catalog (OSS) and seamlessly exposing those exact same Parquet data files to the AWS ecosystem (AWS Glue / Athena) as first-class Apache Iceberg tables.

This project bridges the gap between Databricks-centric and AWS-centric data architectures using purely open-source technologies, explicitly bypassing known structural limitations in the open-source Delta UniForm converter when operating outside of managed Hive Metastores.

## Features

* **Single Copy of Data:** Write once (in Delta format) and query instantly from both Unity Catalog and Iceberg/Glue without data duplication or ETL pipelines.
* **REST API Registration:** Uses Unity Catalog's Native REST API to explicitly register tables, avoiding bugs in the Spark `UCSingleCatalog` integration.
* **Zero-ETL Iceberg Adoption:** Leverages Iceberg's `add_files` procedure to dynamically wrap Delta-generated Parquet files into a valid Iceberg catalog without requiring Delta's internal `IcebergConverter` hooks.
* **Fully Local Multi-Catalog Stack:** Entirely containerized architecture running Spark, Unity Catalog OSS Server, Iceberg REST Catalog, and AWS LocalStack (S3 + Glue) using Docker Compose.
* **Immutable Pipeline:** 100% reproducible Jupyter Notebook phases for step-by-step validation of data state across engines.

## System Architecture

The pipeline runs across a containerized multi-engine stack orchestrated by `docker-compose`:

| Service | Technology | Description |
| :--- | :--- | :--- |
| **Compute Engine** | PySpark (Jupyter) | Data processing and catalog operations orchestrator. |
| **Delta Catalog** | Unity Catalog (OSS) | Primary governance catalog for Delta tables. |
| **Iceberg Catalog** | Iceberg REST Catalog | Intermediate metadata layer for Iceberg. |
| **AWS Cloud (Sim)** | LocalStack | Provides S3-compatible storage and AWS Glue endpoints. |
| **Data Format** | Delta / Iceberg | Open table formats leveraging shared Parquet files. |

### The "Add-Files" Bridge Architecture
Due to limitations in OSS Delta's `IcebergConverter` against embedded Derby metastores, this pipeline uses an explicit adoption strategy:
1.  **Delta Write:** Standard Delta files are written to S3.
2.  **UC Registration:** Table is registered in Unity Catalog.
3.  **Iceberg Adoption:** An empty Iceberg table is created in the Central Catalog (Glue). Iceberg's `add_files` procedure scans the Delta directory and adopts the Parquet files into the Iceberg manifest, bypassing the broken Delta converter entirely.

## Directory Structure

```text
Unity-Glue-Reverse-Sync/
├── phase2_pipeline.ipynb       # Phase 2: Data generation, Delta write, and UC REST API registration
├── phase3_reverse_sync.ipynb   # Phase 3: Iceberg table creation and add_files adoption
├── .gitignore                  # Git exclusions for metastores and logs
├── docker-compose.yaml         # Multi-catalog infrastructure definition
├── init.sh                     # Setup script to provision LocalStack S3 buckets
├── unity_server.properties     # Configuration for the Unity Catalog OSS server
└── LICENSE.md                  # GPLv3 License
```

## Development Setup

### Prerequisites

To run this pipeline locally, you will need:
* **Docker Engine** & **Docker Compose (v2)**
* A system capable of allocating at least 8GB of RAM to Docker.

## Quick Start

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/rdrishabh38/Unity-Glue-Reverse-Sync.git
    cd Unity-Glue-Reverse-Sync
    ```

2.  **Launch the Infrastructure:**
    Bring up the Spark, Unity Catalog, Iceberg REST, and LocalStack containers.
    ```bash
    docker-compose up -d
    ```

3.  **Initialize S3 Storage:**
    Run the initialization script to provision the required S3 buckets in LocalStack.
    ```bash
    ./init.sh
    ```

4.  **Execute the Pipeline:**
    * Open your browser and navigate to `http://localhost:8888` to access the Jupyter environment.
    * Open and run `phase2_pipeline.ipynb` to generate the mock data, write the Delta table, and register it in Unity Catalog.
    * Open and run `phase3_reverse_sync.ipynb` to execute the reverse-sync into the Iceberg/Glue central catalog.

## Common Commands (Justfile)

This project uses [`just`](https://github.com/casey/just) to automate common development tasks.

| Recipe | Description | Command |
| :--- | :--- | :--- |
| `just build` | Build all the Docker images. | `docker compose build` |
| `just up` | Start all services in detached mode. | `docker compose up -d` |
| `just reset` | Wipe out containers/volumes (keep images), then start fresh. | `docker compose down -v ...` |
| `just down` | Stop all running services. | `docker compose down` |
| `just status` | Check the health/status of running containers. | `docker compose ps` |
| `just logs` | Follow logs for all active services. | `docker compose logs -f` |
| `just nuke` | **Danger:** Stop and remove all containers, images, and volumes. | `docker compose down -v --rmi all ...` |

## How It Works

The pipeline executes in sequential phases to ensure structural integrity across catalogs:

1. **Phase 2 (Delta -> Unity Catalog & CRUD Mutations):**
   * Mock data is generated via PySpark and written natively to LocalStack S3 in Delta format.
   * The table is explicitly registered in Unity Catalog via `POST /api/2.1/unity-catalog/tables` to bypass Spark UC plugin bugs.
   * **Mutation Test:** `UPDATE` and `DELETE` operations are applied to the Delta table. 
   * **Critical Prep:** The table is vacuumed with a `RETAIN 0 HOURS` policy to physically delete stale Parquet files orphaned by the CRUD operations, ensuring the directory exactly matches the current logical snapshot.
2. **Phase 3 (Delta -> Iceberg On-Demand Reverse Sync):**
   * The pipeline connects to the `central_catalog` (Iceberg REST/Glue).
   * It drops and recreates the Iceberg table, inferring the schema directly from the underlying Parquet files (`AS SELECT * FROM parquet... WHERE 1=0`).
   * The `CALL central_catalog.system.add_files` procedure natively adopts the physical Parquet files into the Iceberg table manifest.
3. **Phase 4 (Validation):**
   * A simulated Athena read is executed via Spark SQL `SELECT * FROM central_catalog...`. This confirms that the CRUD updates executed in Databricks are correctly reflected in the AWS Glue catalog.

## Architectural Hurdles & Bug Workarounds

This pipeline was designed specifically to bypass several blocking bugs and structural limitations in the current OSS Lakehouse ecosystem (Delta 3.2.x, Unity Catalog OSS 0.2.0):

1. **Unity Catalog OSS Spark Integration Bug:** 
   * **Issue:** The `UCSingleCatalog` Spark plugin fails to properly inject AWS credentials during path-based table creations, and `ReplaceTableAsSelect` commands fail with unresolved external paths.
   * **Workaround:** We bypass the Spark catalog plugin entirely for the write path. We use native Spark `df.write.format("delta").save()` to write the files to S3, and then explicitly call the Unity Catalog REST API (`POST /api/2.1/unity-catalog/tables`) to register the external table.

2. **Delta UniForm Metadata Generation Failure:**
   * **Issue:** Delta OSS UniForm relies on an asynchronous post-commit hook (`IcebergConverter`) to generate Iceberg metadata. This converter is hardcoded to expect a fully-featured Hive Metastore. When running against an embedded Derby metastore or Unity Catalog, the converter encounters a fatal `NullPointerException` when calling `HiveTableOperations.getSd()` because the simulated Hive table lacks a `StorageDescriptor`. Worse, when the commit fails, Iceberg's transaction rollback automatically deletes the orphaned `.metadata.json` file.
   * **Context:** This is a known structural limitation corroborated by [delta-io/delta#3217](https://github.com/delta-io/delta/issues/3217).
   * **Workaround:** We completely dropped the Delta UniForm dependency (`UPGRADE UNIFORM (ICEBERG_COMPAT_VERSION=2)`). Instead, we natively construct the Iceberg table in the Central Catalog and use Iceberg's `add_files` procedure to adopt the raw Delta Parquet files.

3. **The `add_files` Bridge & Zero-Retention Vacuuming Danger:**
   * **Issue:** Because `add_files` blindly scans a directory for Parquet files and does not read the `_delta_log`, it will accidentally adopt stale, pre-update, or deleted files if they still exist in the directory. 
   * **Workaround:** We force a `VACUUM ... RETAIN 0 HOURS` command before running the sync to clear out stale files.
   * **Production Risk:** This workaround is **unsafe for production**. Enforcing a 0-hour retention destroys Delta Time Travel capabilities and will immediately corrupt queries for concurrent readers (throwing `FileNotFoundException` errors). This mathematically proves that a custom `add_files` bridge is not a viable long-term architecture, and managed cross-cloud catalog syncs (like Databricks native AWS Glue Sync) are required for enterprise safety.


## License & Copyright

**Copyright (C) 2026 Rishabh Dixit. All Rights Reserved.**

This project is licensed under the **GNU General Public License v3.0**.
See the [LICENSE.md](LICENSE.md) file for details.

## Disclaimer

* **OSS UniForm Limitations:** This pipeline specifically acts as a workaround for structural limitations in OSS Delta Lake 3.2.0 `IcebergConverter` when operating outside of a managed Hive Metastore. 
* **Column Mapping:** Delta Column Mapping (`name` mode) must remain disabled for this `add_files` architecture to function, as Iceberg requires the physical Parquet column names to match the logical schema.
* **Sync Model:** This POC demonstrates an **on-demand, batch full-refresh** sync model, not a continuous incremental sync. It requires dropping and re-adopting files to capture updates safely.
