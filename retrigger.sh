#!/bin/sh

if [ ! -f ./retrigger.conf ]; then
    echo "The ./retrigger.conf file was not found." >&2
    echo "Read the README.md to learn how to create that file." >&2
    exit 1
fi
    
. ./retrigger.conf

if [ -z "$JENKINS_URL" ]; then
    echo "The JENKINS_URL config value was not found in ./retrigger.conf" >&2
    exit 1
fi

if [ -z "$CURL_OPTIONS" ]; then
    CURL_OPTIONS="-k -s -L"
fi

if [ -z "$JENKINS_JOB_NAME" ]; then
    echo "The JENKINS_JOB_NAME config value was not found in ./retrigger.conf" >&2
    exit 1
fi

if [ -z "$JENKINS_USERID" ]; then
    echo "The JENKINS_USERID config value was not found in ./retrigger.conf" >&2
    exit 1
fi

if [ -z "$JENKINS_PASSWORD" ]; then
    echo "The JENKINS_PASSWORD config value was not found in ./retrigger.conf" >&2
    exit 1
fi

GERRIT_CHANGE=${1}

COOKIES=`mktemp`
CURL_OPTIONS="$CURL_OPTIONS --cookie $COOKIES --cookie-jar $COOKIES"

curl $CURL_OPTIONS ${JENKINS_URL}/login > /dev/null

curl $CURL_OPTIONS --data "j_username=${JENKINS_USERID}&j_password=${JENKINS_PASSWORD}" ${CURL_OPTIONS} ${JENKINS_URL}/j_acegi_security_check > /dev/null

JOBS_PAGE=`mktemp`
curl $CURL_OPTIONS ${JENKINS_URL}/job/${JENKINS_JOB_NAME}/ > $JOBS_PAGE

JOBS=`grep -oe "/job/${JENKINS_JOB_NAME}/[0-9]*/" $JOBS_PAGE | sed s:^/:: | sort | uniq`
rm -Rf $JOBS_PAGE

last_build=
should_retrigger=false
success=false

while ! $success; do
    
    for job in $JOBS; do
        job_page=`curl $CURL_OPTIONS ${JENKINS_URL}/${job}`
        if echo "$job_page" | grep -q "\"$GERRIT_CHANGE\""; then
            last_build=$job
            should_retrigger=false
            if echo "$job_page" | grep -q "alt=\"Failed\""; then
                echo "Job $job is for $GERRIT_CHANGE and it failed"
                RETRIGGER_LINK=/${job}gerrit-trigger-retrigger-this
                echo "\tLooking for $RETRIGGER_LINK"
                if echo "$job_page" | grep -q "$RETRIGGER_LINK"; then
                    should_retrigger=true
                    echo "\tretrigger link found"
                fi
            elif echo "$job_page" | grep -q "alt=\"Success\""; then
                echo "Job $job is for $GERRIT_CHANGE and it passed"
                success=true
                break
            else
                echo "Job $job is for $GERRIT_CHANGE and it looks like it's still in progress"
            fi
        fi
    done
    
    if [ -n "$last_build" ] && $should_retrigger ; then
        RETRIGGER_LINK=$JENKINS_URL/${last_build}gerrit-trigger-retrigger-this
        echo "Retriggering $last_build with $RETRIGGER_LINK"
        curl ${CURL_OPTIONS} $RETRIGGER_LINK > /dev/null
    fi
    
    echo "Waiting a minute before re-checking"
    sleep 60
    
done
    
rm -Rf $COOKIES
    
if $success; then
    exit 0
else
    exit 1
fi


