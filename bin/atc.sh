#!/bin/bash

if ! command -v aws jq >/dev/null 2>&1; then
  echo "Error: Required command is not found."
  exit 1
fi

show_usage() {
  cat << EOS
Usage: $(basename "$0") [OPTIONS] PROFILE

  Get the temporary credentials for AWS.

Options:
  -c PATH  The path of AWS config file. (default: $HOME/.aws/config)
  -d INT   The duration, in seconds, of the role session. (default: 3600)
  -h       Show this message and exit.
EOS
  exit 0
}

usage_error() {
  local error_message=$1
  cat 1>&2 << EOS
$error_message
Try '$(basename "$0") -h' for help.
EOS
  exit 1
}

config_file="$HOME/.aws/config"
duration="3600"

while getopts c:d:h OPT
do
  case $OPT in
    c) config_file=$OPTARG
      ;;
    d) duration=$OPTARG
      ;;
    h) show_usage
      ;;
    \?) usage_error "Error: No such option."
      ;;
  esac
done
shift $((OPTIND - 1))

if [ $# -ne 1 ]; then
  usage_error "Error: Missing argument 'PROFILE'."
fi

read_config() {
  if [ ! -e "$config_file" ]; then
    usage_error "Error: AWS config file is not found: $config_file"
  fi

  local section=$1

  local vars
  vars=$(
    sed \
      -e 's/[[:space:]]*\=[[:space:]]*/=/g' \
      -e 's/;.*$//' \
      -e 's/[[:space:]]*$//' \
      -e 's/^[[:space:]]*//' \
      -e "s/^\(.*\)=\([^\"']*\)$/\1=\"\2\"/" \
      "$config_file" \
    | sed -n -e "/^\[$section\]/,/^\s*\[/{/^[^;].*\=.*/p;}"
  )
  eval "$vars"
}

profile_name=$1
role_arn=""
source_profile=""
mfa_serial=""
read_config "profile $profile_name"

if [ -n "$role_arn" ]; then
  options="--role-arn $role_arn"
else
  usage_error "Error: Invalid or missing value for 'role_arn' in 'profile $profile_name'."
fi
options="$options \
  --role-session-name session-$(date +%s) \
  --duration-seconds $duration"
if [ -n "$source_profile" ]; then
  options="$options --profile $source_profile"
fi
if [ -n "$mfa_serial" ]; then
  token_code=""
  echo -n "MFA Token Code: "
  read -r token_code
  options="$options \
    --serial-number $mfa_serial \
    --token-code $token_code"
fi

output=$(eval "aws sts assume-role $options")
exit_status=$?

if [ $exit_status == 0 ]; then
  echo "export AWS_ACCESS_KEY_ID=$(echo "$output" | jq -r .Credentials.AccessKeyId)"
  echo "export AWS_SECRET_ACCESS_KEY=$(echo "$output" | jq -r .Credentials.SecretAccessKey)"
  echo "export AWS_SESSION_TOKEN=$(echo "$output" | jq -r .Credentials.SessionToken)"
else
  exit $exit_status
fi
