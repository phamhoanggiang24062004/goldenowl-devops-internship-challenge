def runBash(String script) {
  if (isUnix()) {
    sh script
  } else {
    writeFile file: 'jenkins-step.sh', text: script
    bat '"C:\\Program Files\\Git\\bin\\bash.exe" jenkins-step.sh'
  }
}

pipeline {
  agent any

  environment {
    IMAGE_NAME = 'goldenowl-devops-internship-challenge'
    CONTAINER_NAME = 'Nodejs-app-container'
    APP_CONTAINER_NAMES = 'Nodejs-app-container'
    HOST_PORT = '3000'
    CONTAINER_PORT = '3000'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        script {
          runBash '''
            echo "Commit=$(git rev-parse HEAD)"
            echo "Branch=$(git rev-parse --abbrev-ref HEAD)"
          '''
        }
      }
    }

    stage('Print trigger context') {
      steps {
        script {
          runBash '''
            echo "BUILD_ID=${BUILD_ID}"
            echo "JOB_NAME=${JOB_NAME}"
            echo "BRANCH_NAME=${BRANCH_NAME:-unknown}"
            echo "GIT_COMMIT=$(git rev-parse HEAD)"
          '''
        }
      }
    }

    stage('CD') {
      steps {
        withCredentials([
          usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_TOKEN'),
          sshUserPrivateKey(credentialsId: 'ec2-ssh-key', keyFileVariable: 'EC2_SSH_KEY_FILE', usernameVariable: 'EC2_SSH_USER'),
          string(credentialsId: 'ec2-host', variable: 'EC2_HOST'),
          string(credentialsId: 'ec2-ssh-port', variable: 'EC2_SSH_PORT')
        ]) {
          script {
            runBash '''
              export DOCKERHUB_USERNAME="$DOCKERHUB_USERNAME"
              export DOCKERHUB_TOKEN="$DOCKERHUB_TOKEN"
              export EC2_HOST="$EC2_HOST"
              export EC2_USER="${EC2_SSH_USER}"
              export EC2_SSH_PRIVATE_KEY="$(cat "$EC2_SSH_KEY_FILE")"
              export EC2_SSH_PORT="${EC2_SSH_PORT:-22}"
              export IMAGE_NAME="${IMAGE_NAME}"
              export IMAGE_TAG="$(git rev-parse HEAD)"
              export CONTAINER_NAME="${CONTAINER_NAME}"
              export APP_CONTAINER_NAMES="${APP_CONTAINER_NAMES}"
              export HOST_PORT="${HOST_PORT}"
              export CONTAINER_PORT="${CONTAINER_PORT}"

              bash scripts/cd.sh
            '''
          }
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'logs/**', allowEmptyArchive: true
    }
  }
}

