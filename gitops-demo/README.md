# Jenkins to Argo CD GitOps demo

Flow:

```text
GitHub → Jenkins → test
                  ├── artifact → S3
                  ├── image → ECR
                  └── image tag → Git Helm values
                                      ↓
                                  Argo CD → EKS
```

Jenkins never deploys the application with `kubectl`. It builds the artifact and
image, then updates Git. Argo CD owns deployment to EKS.

## 1. Jenkins EC2 requirements

Install Git, Docker, AWS CLI v2, Python 3, Helm 3, curl, tar and sha256sum. Give
the Jenkins user Docker access:

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

Use an EC2 instance profile for AWS access. Do not save AWS keys in Jenkins.

## 2. Create ECR and the S3 artifact bucket

Run from an AWS administrator shell. The bucket name must be globally unique.

```bash
cd gitops-demo
chmod +x aws/bootstrap.sh
export AWS_REGION=ap-south-1
export ECR_REPOSITORY=gitops-demo
export ARTIFACT_BUCKET=replace-with-a-unique-bucket
./aws/bootstrap.sh
```

Replace the placeholders in `aws/jenkins-ec2-iam-policy.json`, create an IAM
policy from it, and attach that policy to the Jenkins EC2 role. The EKS node role
also needs ECR pull permission.

## 3. Configure Jenkins

Add a GitHub fine-grained token with repository Contents read/write as a Jenkins
**Username with password** credential named `github-pat`.

Create a **Pipeline from SCM** job:

- Repository: `https://github.com/suryakant1811/argocd.git`
- Branch: `*/main`
- Script path: `gitops-demo/Jenkinsfile`
- `ARTIFACT_BUCKET`: the bucket created above

Defaults are `ap-south-1`, ECR repository `gitops-demo`, branch `main`, and
credential `github-pat`.

The first build validates Helm, packages and smoke-tests the application,
uploads its artifact to S3, pushes a Git-SHA-tagged image to ECR, and commits the
real ECR URI and immutable tag to `helm-values/prod/values.yaml`.

The generated commit contains `[gitops-skip]`, preventing a build loop.

## 4. Create the Argo CD application

Do this after the first successful Jenkins build has replaced the placeholder
ECR account:

```bash
kubectl apply -f gitops-demo/argocd/application.yaml
kubectl get application gitops-demo-prod -n argocd
kubectl get pods,svc -n prod
```

Open the application:

```bash
kubectl port-forward service/gitops-demo -n prod 8080:80
```

Browse to `http://localhost:8080`.

## Rollback

Revert the Git commit that changed the production image:

```bash
git revert <commit>
git push origin main
```

Argo CD detects the revert and deploys the previous immutable ECR image.
