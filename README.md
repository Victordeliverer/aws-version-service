# aws-version-service

A small Java service used to learn Gradle and a full AWS CI/CD flow end to end: build once, store a versioned artifact, deploy that exact artifact, run it as a Linux service.

## Pipeline

```
GitHub (main)
   |
   v
AWS CodePipeline
   |
   v
AWS CodeBuild         Gradle: test + build + publish
   |
   v
AWS CodeArtifact      stores the versioned JAR (immutable)
   |
   v
AWS CodeDeploy        runs hook scripts on the instance
   |
   v
EC2 (Amazon Linux 2023)   fetches that exact JAR from CodeArtifact, runs it under systemd
```

**Design note:** CodeDeploy can only deploy a bundle from S3, so the pipeline's deploy bundle contains only `appspec.yml`, `version.txt` and the `deploy/` scripts, not the JAR. On the instance, `install.sh` downloads the JAR by version from CodeArtifact. This makes CodeArtifact the single source of truth for what runs in production.

## The application

A plain Java 21 app using the JDK's built-in HTTP server on port 8080. It responds with a greeting that includes its own version, read from the JAR manifest (`Implementation-Version`), so you can always see which build is live.

```bash
curl localhost:8080
# Hello from ... version 1.0.<build-number>
```

## Repository layout

```
.
├── app/
│   ├── build.gradle                 Gradle config: jar, manifest, maven-publish
│   └── src/{main,test}/java/com/victordeliverer/versionservice/
├── deploy/
│   ├── hello-svc.service            systemd unit
│   ├── stop.sh                      ApplicationStop hook
│   ├── install.sh                   AfterInstall hook: pull JAR from CodeArtifact
│   ├── start.sh                     ApplicationStart hook
│   └── validate.sh                  ValidateService hook: curl health check
├── appspec.yml                      CodeDeploy lifecycle definition
├── buildspec.yml                    CodeBuild steps
├── gradlew, gradle/                 Gradle wrapper
└── settings.gradle
```

## Run locally

Requires JDK 21. Run all Gradle commands from the repository root.

```bash
APP_VERSION=1.0.0 ./gradlew clean build
java -jar app/build/libs/aws-version-service-1.0.0.jar
curl localhost:8080
```

## Versioning

- The version comes from the `APP_VERSION` environment variable (`build.gradle`), falling back to `0.1.0-SNAPSHOT` locally.
- In CodeBuild it is set to `1.0.${CODEBUILD_BUILD_NUMBER}`, so every build gets a unique version.
- Released Maven versions in CodeArtifact are immutable and cannot be overwritten.

## AWS resources (region eu-west-1)

| Resource | Name |
|---|---|
| CodeArtifact domain / repository | `gradle-lab` / `app-releases` |
| Package coordinates | `com.victordeliverer:aws-version-service` |
| CodeBuild project | `aws-version-service-build` |
| CodeDeploy application / group | `aws-version-service` / `aws-version-service-dg` |
| Pipeline | `aws-version-service-pipeline` |
| EC2 instance tag | `Name = aws-version-service` |

### IAM roles: each service has its own

| Role | Purpose | Key permissions |
|---|---|---|
| CodeBuild service role | Build and publish | CodeArtifact publish and token (`codeartifact:*` actions, `sts:GetServiceBearerToken`) |
| CodePipeline service role | Orchestrate stages | CodeDeploy deployment actions (`codedeploy:CreateDeployment` and related) |
| CodeDeploy service role | Reach the instance | `AWSCodeDeployRole` |
| EC2 instance role | Run deployments | SSM core, S3 read (deploy bundle), CodeArtifact read |

## CodeDeploy lifecycle

| Hook | Script | Action |
|---|---|---|
| ApplicationStop | `stop.sh` | Stop the service |
| (file copy) | n/a | Place `version.txt` and the systemd unit |
| AfterInstall | `install.sh` | Download the JAR from CodeArtifact, update `current.jar` symlink |
| ApplicationStart | `start.sh` | `systemctl start` |
| ValidateService | `validate.sh` | Retry `curl localhost:8080` |

JARs are kept in `/opt/hello-svc/releases/`, and `current.jar` is a symlink to the active one, which makes rollback a one-line change.

## Troubleshooting notes (issues hit while building this)

| Symptom | Cause | Fix |
|---|---|---|
| `Unable to locate a Java Runtime` | Homebrew `openjdk` is keg-only, not on `PATH` | Export `JAVA_HOME` and `PATH` in the shell's startup file (bash: `~/.bash_profile`, zsh: `~/.zshrc`) |
| `Project directory ... is not part of the build` | Ran Gradle from a non-project folder (`deploy/`) | Run `./gradlew` from the repository root |
| JAR named `app.jar` | No `version` / `archiveBaseName` set | Set both in `app/build.gradle` |
| Deploy stage: `PermissionError ... codedeploy:CreateDeployment` | Pipeline role had no CodeDeploy permissions (created before the application existed) | Add an inline policy with the CodeDeploy actions |
| `list-deployments` returns nothing | Deploy action failed before CodeDeploy created a deployment | Read the action's `errorDetails` via `aws codepipeline get-pipeline-state` |
| `ResourceNotFoundException` on package | Wrong namespace or package name in `install.sh` | Use `com.victordeliverer` / `aws-version-service` |
| Empty `buildspec.yml` | File never written | Recreate it; CodeBuild fails on an empty file |

## Useful commands

```bash
# Stage status
aws codepipeline get-pipeline-state --region eu-west-1 --name aws-version-service-pipeline \
  --query "stageStates[].{stage:stageName,status:latestExecution.status}" --output table

# Published versions
aws codeartifact list-package-versions --region eu-west-1 --domain gradle-lab \
  --repository app-releases --format maven --namespace com.victordeliverer \
  --package aws-version-service --query "versions[].version" --output text

# On the instance
systemctl status hello-svc
journalctl -u hello-svc
tail -n 50 /var/log/aws/codedeploy-agent/codedeploy-agent.log
```

## Possible next steps

- Build a fat JAR (Shadow plugin) so third-party dependencies are bundled
- Resolve dependencies through CodeArtifact with an upstream to Maven Central
- Add a load balancer and blue/green or rolling deployments
- Scope IAM policies to specific resources instead of `*`
- Add alarms and logs (CloudWatch agent) for the service

## Cleanup

Delete the pipeline, CodeBuild project, CodeDeploy application, EC2 instance, the pipeline's S3 artifact bucket, and the CodeArtifact repository and domain. Then remove the IAM roles and the GitHub connection.
