# RKE2 ETCDiag

> A Bash-based diagnostic and maintenance tool for RKE2 (Rancher Kubernetes Engine 2) ETCD clusters.

---

## 🧩 Overview

**RKE2 ETCDiag** is a comprehensive command-line tool that scans directories for valid `kubeconfig` files, connects to RKE2 Kubernetes clusters, and provides a rich set of ETCD health checks, object summaries, and maintenance capabilities like compaction and defragmentation. It's designed to help cluster operators easily inspect and manage ETCD state across multiple clusters.

---

## 🔧 Features

- ✅ Validate and list all available `kubeconfig` files.
- 🔐 Test admin access to each cluster.
- 📊 Display ETCD DB size, version, leadership status, and sync information.
- 🧮 Show most numerous objects in ETCD.
- 🧹 Perform ETCD compaction and defragmentation.
- 🧭 Interactive CLI menu with arrow navigation.
- 🕵️ Quick diagnostic across all found clusters.

---

## 📦 Requirements

- `bash`
- `kubectl`
- Administrator access to RKE2 Kubernetes clusters (via valid `kubeconfig` files).
- `etcdctl` binary must be present in the etcd pods (default in RKE2)
- Script run with enough privileges to exec into etcd pods

---

## Installation

Clone or download this repository and place the script somewhere on the same server as your kubeconfig files. Add execution rights to the script.

```bash
chmod +x rke2-etcd-diag.sh
```

---

## Usage

Run the script and point it to a folder containing kubeconfig files:

```bash
./rke2-etcd-diag.sh /path/to/kubeconfigs
```

If no directory is specified, the current directory (`.`) will be used.

### Main Menu Options

- **Quick diag all ETCD databases**: For all cluster (kubeconfigs) found: Displays database size, version, leader status, raft info, and any errors.
- **[cluster name]**: Dive into specific checks and actions per cluster.

### Cluster Menu Options

- **Check etcd size and sync**: Displays database size, version, leader status, raft info, and any errors.
- **Check top objects by quantity**: Lists the most stored object types in etcd.
- **Compact and defrag**: Executes a compaction and defragmentation of the etcd database.

---

## Example Output

```
Checking etcd size and synchronization for cluster my-rke2-cluster...

NODE NAME                                         NODE IP         DB SIZE    VERSION    LEADER   LEARNER  RAFT TERM  RAFT INDEX  ERRORS
master01                                         10.42.0.1       10MB       3.5.7      true     false    125        15023       
master02                                         10.42.0.2       10MB       3.5.7      false    false    125        15023       
```

---

## Disclaimer

This tool is intended for **diagnostic and operational use only**. It is advised to use caution when compacting or defragmenting production etcd clusters.

### ⚠️ Warning
This script modifies ETCD clusters. Use it with caution and **always ensure you have a full backup before taking any action on etcd.**
