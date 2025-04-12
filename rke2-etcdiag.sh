#!/bin/bash

# RKE2 ETCDiag - ETCD Diagnostic Tool for rancher RKE2 clusters 
# This script analyzes one or more etcd clusters using kubeconfig files

# Colors for the interface
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
ORANGE='\033[38;5;214m'
NC='\033[0m' # No Color

NON_INTERACTIVE=false

# Function to display information messages
info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

# Function to display success messages
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# Function to display error messages
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to display alert messages
alert() {
    echo -e "${RED}[ALERT!]${NC} $1" >&2
}

# Function to display warning messages
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if kubectl is installed
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it before using this script."
        exit 1
    else
        success "kubectl is installed."
    fi
}

# Find all kubeconfig files in the specified directory
find_kubeconfigs() {
    local dir="$1"
    local found_files=()

    # Check if the directory exists
    if [ ! -d "$dir" ]; then
        error "Directory '$dir' does not exist."
        exit 1
    fi

    info "Searching for kubeconfig files in $dir"

    # Find all yaml/yml files
    while IFS= read -r -d '' file; do
        if grep -q "kind: Config" "$file" 2>/dev/null && grep -q "clusters:" "$file" 2>/dev/null; then
            success "Valid kubeconfig found: $file"
            found_files+=("$file")
        fi
    done < <(find "$dir" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0 2>/dev/null)

    if [ ${#found_files[@]} -eq 0 ]; then
        error "No valid kubeconfig files found in '$dir'."
        return 1
    fi

    # Output valid kubeconfig file paths, one per line
    for kubeconfig in "${found_files[@]}"; do
        echo "$kubeconfig"
    done

    # Store or return found files as needed (e.g., set a global or export)
}

# Verify admin access to the cluster with a kubeconfig
verify_kubeconfig() {
    local kubeconfig="$1"
    local cluster_name=$(get_cluster_name "$kubeconfig")
    
    info "Verifying access to cluster ${ORANGE}$cluster_name${NC} with $kubeconfig..."
    
    if ! kubectl --kubeconfig="$kubeconfig" get nodes &> /dev/null; then
        warning "Unable to access cluster as cluster admin with $kubeconfig."
        return 1
    else
        success "Cluster admin access confirmed to cluster ${ORANGE}$cluster_name${NC}."
        return 0
    fi
}

# Get the cluster name from the kubeconfig
# Get the cluster name from the kubeconfig
get_cluster_name() {
    local kubeconfig="$1"
    local cluster_name=""
    
    if [ -f "$kubeconfig" ]; then
        cluster_name=$(grep -A1 "clusters:" "$kubeconfig" 2>/dev/null | grep "name:" | head -1 | awk '{print $3}' | tr -d '"')
    fi
    
    # If the name is not found, use the filename
    if [ -z "$cluster_name" ]; then
        cluster_name=$(basename "$kubeconfig" | sed 's/\.[^.]*$//')
    fi
    
    echo "$cluster_name"
}
# Function to check etcd size and synchronization
check_etcd_size_and_sync() {
    local kubeconfig="$1"
    local cluster_name=$(get_cluster_name "$kubeconfig")
    
    info "Checking etcd size and synchronization for cluster ${ORANGE}$cluster_name${NC}..."
    
    # Print the header
    printf "%-52s %-15s %-10s %-10s %-9s %-9s %-12s %-13s %s\n" "NODE NAME" "NODE IP" "DB SIZE" "VERSION" "LEADER" "LEARNER" "RAFT TERM" "RAFT INDEX" "ERRORS"

    # Iterate through etcd pods and collect status
    for etcdpod in $(kubectl --kubeconfig="$kubeconfig" -n kube-system get pod -l component=etcd --no-headers -o custom-columns=NAME:.metadata.name); do
    
        # Get the node name where this pod is running
        nodeName=$(kubectl --kubeconfig="$kubeconfig" -n kube-system get pod $etcdpod -o jsonpath='{.spec.nodeName}')
        
        # Get the node IP address
        nodeIP=$(kubectl --kubeconfig="$kubeconfig" get node $nodeName -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    
        # Get the raw output
        output=$(kubectl --kubeconfig="$kubeconfig" -n kube-system exec $etcdpod -- sh -c "ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' ETCDCTL_CACERT='/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt' ETCDCTL_CERT='/var/lib/rancher/rke2/server/tls/etcd/server-client.crt' ETCDCTL_KEY='/var/lib/rancher/rke2/server/tls/etcd/server-client.key' ETCDCTL_API=3 etcdctl endpoint status")
        
        # Process each line
        echo "$output" | grep -v "ENDPOINT" | while read -r line; do
            # Parse the CSV-like output
            # endpoint=$(echo "$line" | cut -d ',' -f 1 | xargs)
            # id=$(echo "$line" | cut -d ',' -f 2 | xargs)
            version=$(echo "$line" | cut -d ',' -f 3 | xargs)
            dbsize=$(echo "$line" | cut -d ',' -f 4 | xargs)
            isLeader=$(echo "$line" | cut -d ',' -f 5 | xargs)
            isLearner=$(echo "$line" | cut -d ',' -f 6 | xargs)
            raftTerm=$(echo "$line" | cut -d ',' -f 7 | xargs)
            raftIndex=$(echo "$line" | cut -d ',' -f 8 | xargs)
            raftApplied=$(echo "$line" | cut -d ',' -f 9 | xargs)
            errors=$(echo "$line" | cut -d ',' -f 10- | xargs)
            
            # Print formatted row
            printf "%-52s %-15s %-10s %-10s %-9s %-9s %-12s %-13s %s\n" "$nodeName" "$nodeIP" "$dbsize" "$version" "$isLeader" "$isLearner" "$raftTerm" "$raftIndex" "$errors"
        done
    done

    # Skip "Press Enter" if NON_INTERACTIVE is true
    if [ "$NON_INTERACTIVE" = false ]; then
        echo -e "\nPress Enter to continue..."
        read
    fi
}

# Function to check the most numerous objects
check_top_objects() {
    local kubeconfig="$1"
    local cluster_name=$(get_cluster_name "$kubeconfig")
    
    info "Checking top objects by quantity for cluster ${ORANGE}$cluster_name${NC}..."
    
    kubectl --kubeconfig="$kubeconfig" -n kube-system exec $(kubectl --kubeconfig="$kubeconfig" -n kube-system get pod -l component=etcd --no-headers -o custom-columns=NAME:.metadata.name | head -n 1) -- etcdctl --cert /var/lib/rancher/rke2/server/tls/etcd/server-client.crt --key /var/lib/rancher/rke2/server/tls/etcd/server-client.key --cacert /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt get /registry --prefix=true --keys-only | grep -v ^$ | awk -F'/' '{ if ($3 ~ /cattle.io/) {h[$3"/"$4]++} else { h[$3]++ }} END { for(k in h) print h[k], k }' | sort -nr
    
    echo -e "\nPress Enter to continue..."
    read
}

# Function to compact and defragment etcd
compact_and_defrag() {
    local kubeconfig="$1"
    local cluster_name=$(get_cluster_name "$kubeconfig")
    
    info "Compacting and defragmenting etcd for cluster ${ORANGE}$cluster_name${NC}..."
    
    # Get the current revision
    local rev=$(kubectl --kubeconfig="$kubeconfig" -n kube-system exec $(kubectl --kubeconfig="$kubeconfig" -n kube-system get pod -l component=etcd --no-headers -o custom-columns=NAME:.metadata.name | head -n 1) -- etcdctl --cert /var/lib/rancher/rke2/server/tls/etcd/server-client.crt --key /var/lib/rancher/rke2/server/tls/etcd/server-client.key --cacert /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt endpoint status --write-out fields | grep Revision | cut -d: -f2)
    rev=$(echo $rev | tr -d '"')
    
    info "Current revision: $rev"
    info "Compacting up to revision $rev..."
    
    # Compact
    kubectl --kubeconfig="$kubeconfig" -n kube-system exec $(kubectl --kubeconfig="$kubeconfig" -n kube-system get pod -l component=etcd --no-headers -o custom-columns=NAME:.metadata.name | head -n 1) -- etcdctl --cert /var/lib/rancher/rke2/server/tls/etcd/server-client.crt --key /var/lib/rancher/rke2/server/tls/etcd/server-client.key --cacert /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt compact "$rev"
    
    # Defragment
    info "Defragmenting the cluster..."
    kubectl --kubeconfig="$kubeconfig" -n kube-system exec $(kubectl --kubeconfig="$kubeconfig" -n kube-system get pod -l component=etcd --no-headers -o custom-columns=NAME:.metadata.name | head -n 1) -- etcdctl --cert /var/lib/rancher/rke2/server/tls/etcd/server-client.crt --key /var/lib/rancher/rke2/server/tls/etcd/server-client.key --cacert /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt defrag --cluster
    
    # Check status after compaction and defragmentation
    info "Checking status after compaction and defragmentation..."
    for etcdpod in $(kubectl --kubeconfig="$kubeconfig" -n kube-system get pod -l component=etcd --no-headers -o custom-columns=NAME:.metadata.name); do 
        echo -e "${YELLOW}etcd pod: $etcdpod${NC}"
        kubectl --kubeconfig="$kubeconfig" -n kube-system exec $etcdpod -- sh -c "ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' ETCDCTL_CACERT='/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt' ETCDCTL_CERT='/var/lib/rancher/rke2/server/tls/etcd/server-client.crt' ETCDCTL_KEY='/var/lib/rancher/rke2/server/tls/etcd/server-client.key' ETCDCTL_API=3 etcdctl endpoint status"
        echo ""
    done
    
    echo -e "\nPress Enter to continue..."
    read
}

# Function to quickly diagnose all clusters
quick_diag_all() {
    info "Quick diagnosis of all available clusters..."
    
    # Enable non-interactive mode to skip wait for "Enter" keyboard inputs 
    NON_INTERACTIVE=true

    for kubeconfig in "${valid_kubeconfigs[@]}"; do
        local cluster_name=$(get_cluster_name "$kubeconfig")
        echo -e "\n"
        check_etcd_size_and_sync "$kubeconfig"
    done

    # Restore interactive mode
    NON_INTERACTIVE=false

    echo -e "\nPress Enter to continue..."
    read
}

# Function to create a selectable menu with arrows
# Source: https://unix.stackexchange.com/a/415155
select_option() {
    # Parameters
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    
    # Variables
    local selected=0
    local key
    
    # Hide cursor
    tput civis
    
    # Save original terminal state
    local term_state
    term_state=$(stty -g)
    
    # Set terminal to raw mode
    stty raw -echo
    
    # Show menu and get user selection
    while true; do
        # Clear screen
        tput clear

        # Display title
        echo -e "${ORANGE}${title}${NC}"
        echo ""
        
        # Display options
        for i in "${!options[@]}"; do
            tput cup $((i + 2)) 0 # Place the cursor
            if [ $i -eq $selected ]; then
                echo -e "${ORANGE}> ${options[$i]}${NC}"
            else
                echo "  ${options[$i]}"
            fi
        done
        
        # Read user input
        IFS= read -r -n1 key
        
        # Process key
        case "$key" in
            $'\x1B')  # Start of ESC sequence
                read -rsn2 key  # Read the rest of the escape sequence
                if [ "$key" = "[A" ]; then  # Up arrow
                    ((selected--))
                    [ $selected -lt 0 ] && selected=$((num_options-1))
                elif [ "$key" = "[B" ]; then  # Down arrow
                    ((selected++))
                    [ $selected -ge $num_options ] && selected=0
                fi
                ;;
            "")  # Enter key
                break
                ;;
            "q")  # Quit
                # Restore terminal state
                stty "$term_state"
                tput cnorm
                exit 0
                ;;
        esac
    done
    
    # Restore terminal state
    stty "$term_state"
    tput cnorm
    
    return $selected
}

# Main menu
show_main_menu() {
    clear
    local title="===== RKE2 ETCDiag - ETCD Diagnostic Tool for RKE2 clusters ====="
    
    local options=("Quick diag all ETCD databases")
    for kubeconfig in "${valid_kubeconfigs[@]}"; do
        options+=("$(get_cluster_name "$kubeconfig")")
    done
    options+=("Quit")
    
    select_option "$title" "${options[@]}"
    local choice=$?
    
    if [ $choice -eq 0 ]; then
        quick_diag_all
        show_main_menu
    elif [ $choice -eq $(( ${#options[@]} - 1 )) ]; then
        info "Goodbye!"
        exit 0
    elif [ $choice -gt 0 ] && [ $choice -lt $(( ${#options[@]} - 1 )) ]; then
        show_cluster_menu "${valid_kubeconfigs[$choice-1]}"
    fi
}

# Cluster menu
show_cluster_menu() {
    local kubeconfig="$1"
    local cluster_name=$(get_cluster_name "$kubeconfig")
    
    clear
    local title="===== ETCDiag - Cluster: $cluster_name ====="
    
    local options=("Check etcd size and sync" "Check top objects by quantity" "Compact and defrag" "Back")
    
    select_option "$title" "${options[@]}"
    local choice=$?
    
    case $choice in
        0)
            check_etcd_size_and_sync "$kubeconfig"
            show_cluster_menu "$kubeconfig"
            ;;
        1)
            check_top_objects "$kubeconfig"
            show_cluster_menu "$kubeconfig"
            ;;
        2)
            compact_and_defrag "$kubeconfig"
            show_cluster_menu "$kubeconfig"
            ;;
        3)
            show_main_menu
            ;;
    esac
}

# Main script
main() {
    # Welcome message
    clear
    echo -e "${BLUE}===== RKE2 ETCDiag - ETCD Diagnostic Tool for RKE2 clusters =====${NC}"
    echo "This tool helps diagnose and manage RKE2 ETCD clusters using kubeconfig files."
    echo ""
    
    # Check if kubectl is installed
    check_kubectl
    
    # Check for input directory or use current directory
    local directory="${1:-.}"
    info "Using directory: $directory"
    
    # Find and verify kubeconfig files
    mapfile -t kubeconfig_array < <(find_kubeconfigs "$directory")
    if [ $? -ne 0 ]; then
        error "No kubeconfig files found. Exiting."
        exit 1
    fi
    
    # Verify kubeconfig files
    valid_kubeconfigs=()
    for kubeconfig in "${kubeconfig_array[@]}"; do
        if verify_kubeconfig "$kubeconfig"; then
            valid_kubeconfigs+=("$kubeconfig")
        fi
    done
    
    if [ ${#valid_kubeconfigs[@]} -eq 0 ]; then
        error "No valid kubeconfig files found. Exiting."
        exit 1
    fi
    
    success "Found ${#valid_kubeconfigs[@]} valid kubeconfig file(s)."
    echo -e "\nPress Enter to continue to the main menu..."
    read
    
    # Show main menu
    show_main_menu
}

# Run the script
main "$@"
