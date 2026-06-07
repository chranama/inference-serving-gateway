# EKS Module

Implements the bounded EKS substrate for the AWS slice:

- EKS control plane
- bounded managed node group
- cluster naming and tagging
- outputs needed by later add-on and workload slices

First-slice goal:

- keep the cluster minimal and reviewer-friendly
- preserve one bounded node-group shape rather than prematurely optimizing for HA or autoscaling
