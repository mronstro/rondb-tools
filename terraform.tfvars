region="eu-north-1"

# Set this variable to number of AZs to use, number larger than
# 1 means multi-AZ environment and 1 means single-AZ. Defaults to 1.
num_azs=2

#CPU platform used by the VMs, can currently have 1 at a time and
#choice is between the default x86_64 and arm64_v8.
cpu_platform="arm64_v8"

#glibc version of RonDB tarball
glibc_version="2.28"

#When creating installation script we need to know which RonDB version
#to use. Defaults to "24.10.1".
rondb_version="24.10.2"

#When creating config.ini we need to set number of replicas in RonDB.
#Defaults to 2, number of ndbmtd_count must be a multiple of this
#number.
rondb_replicas=2

#ndb_mgmd_instance_type="t3.xlarge"
ndb_mgmd_instance_type="c8g.large"

ndbmtd_count=10
ndbmtd_instance_type="c8g.2xlarge"
#ndbmtd_instance_type="c7a.4xlarge"

mysqld_count=1
#mysqld_instance_type="t3.2xlarge"
mysqld_instance_type="c8g.large"

rdrs_count=2
rdrs_instance_type="c8g.2xlarge"
#rdrs_instance_type="c7a.4xlarge"

prometheus_instance_type="c8g.medium"

grafana_instance_type="c8g.medium"

bench_count=2
bench_instance_type="c8g.2xlarge"
#bench_instance_type="c7a.12xlarge"

# The name of the AWS key that will be created. No need to change this.
key_name="rondb_bench_key"
