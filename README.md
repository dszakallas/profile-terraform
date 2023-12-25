# profile-terraform

Terraform configuration for my static blog site at https://szakallas.eu

## Quick start

Everything is managed except the Route 53 Hosted Zone.

1. <domain> Buy a domain, create hosted zone, register DNS manually.
2. `terraform apply -var="domain=<domain>" -var="bucket=<bucket>" -var="distribution=MyFancyBlog"`

Note: the `distribution` parameter is used as prefix for certain resources such as IAM Roles to make it easier to identify and prevent name clashes in case you wish to create multiple blogs.

## Content
That is in [a separate repo](https://github.com/dszakallas/profile).
