# See also: https://github.com/wwalker/ssh-find-agent
#
## SSH
SSH_ENV=${SSH_ENV:-"$HOME/.ssh/environment"}
SSH_KEYS="${SSH_KEYS:-}"

## Stop on logout
# See http://jowisoftware.de/wp/2012/04/managing-ssh-agent-automatically-with-cygwinputty-support/
if [[ "$OSTYPE" = cygwin ]] ; then
__instances_tgt=1
_count_instances () {
    ps | grep -wc [m]intty
}
else
__instances_tgt=2
function _count_instances() {
    # ps aux | grep -wc [b]ash
    # The fact this is called in a function adds one to number bash
    # processes detected -> __instances_tgt=2
    pgrep -u $USER bash | wc -l
}
fi

_on_exit_stop_agent() {
    local nb_instances=$(_count_instances)
    if [ ${nb_instances} -eq ${__instances_tgt} ] ; then
        echo "Terminating ssh-agent"
        ssh-add   -D >/dev/null 2>&1
        ssh-agent -k >/dev/null 2>&1
    else
        echo "$((${nb_instances}-1)) terminals still running. ssh-agent is kept."
    fi
}
trap '_on_exit_stop_agent' EXIT

# start the ssh-agent
function start_agent {
    echo "Initializing new SSH agent..."
    # spawn ssh-agent
    test -f "${SSH_ENV}" && rm "${SSH_ENV}"
    ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    echo succeeded
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
    ssh-add ${SSH_KEYS}
}

# test for identities
function test_identities {
    # test whether standard identities have been added to the agent already
    ssh-add -l | grep "The agent has no identities" > /dev/null
    if [ $? -eq 0 ]; then
        ssh-add ${SSH_KEYS}
        # $SSH_AUTH_SOCK broken so we start a new proper agent
        if [ $? -eq 2 ];then
            start_agent
        fi
    fi
}

if [ ${SSH_AGENT_IS_HIDDEN:-0} -eq 1 ] ; then
    # Sometimes, I'm on a machine that hides ssh-agent process.
    # Let's instead suppose that if ssh-add -l returns a valid number
    # which means there is an agent running around
function _ssh_test_agent {
    ssh-add -l > /dev/null 2>&1
}
else
function _ssh_test_agent {
    ps -ef | grep $SSH_AGENT_PID | grep ssh-agent > /dev/null
}
fi

function _ssh_run_env {
    # if $SSH_AGENT_PID is not properly set, we might be able to load one from
    # $SSH_ENV
    . "${SSH_ENV}" > /dev/null
    _ssh_test_agent && test_identities || start_agent
}

# check for running ssh-agent with proper $SSH_AGENT_PID
[ -n "$SSH_AGENT_PID" ] && _ssh_test_agent \
&& test_identities \
|| _ssh_run_env

return

# This (old) version generates the following error message:
#  Usage : grep [OPTION]... PATTERN [FILE]...
ps -ef | grep $SSH_AGENT_PID | grep ssh-agent > /dev/null
if [ $? -eq 0 ]; then
    test_identities
# if $SSH_AGENT_PID is not properly set, we might be able to load one from
# $SSH_ENV
else
    . "${SSH_ENV}" > /dev/null
    ps -ef | grep $SSH_AGENT_PID | grep ssh-agent > /dev/null
    if [ $? -eq 0 ]; then
        test_identities
    else
        start_agent
    fi
fi
