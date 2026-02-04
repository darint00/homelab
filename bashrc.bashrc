#!/bin/bash


export PS1="\[\e[31m\][\[\e[m\]\[\e[38;5;214m\]\u\[\e[m\]@\[\e[38;5;78m\]\h\[\e[m\] \[\e[38;5;214m\]\W\[\e[m\]\[\e[31m\]]\[\e[m\]\\$ "

export GITREPOS=~darint/GITREPOS
export K8SDIR=$GITREPOS/k8s

found=`grep "Added Hosts" /etc/hosts|wc -l`
if [[ "$found" == "0" ]]; then
  sudo $GITREPOS/mach-setup/wsl2/Files/bin/addhosts
fi


if [ -f ${GITREPOS}/k8s/set.aliases ]; then . ${GITREPOS}/k8s/set.aliases; fi
if [ -f ${GITREPOS}/gr/set.aliases ]; then . ${GITREPOS}/gr/set.aliases; fi
if [ -f ${GITREPOS}/dock/set.aliases ]; then . ${GITREPOS}/dock/set.aliases; fi


export PATH=$PATH:.:$GITREPOS/k8s
export PATH=$PATH:.:$GITREPOS/gr
export PATH=$PATH:.:${GITREPOS}/mach-setup/wsl2/Files/bin:${GITREPOS}/utils 

unalias ls
alias k="kubectl"
alias setkube=". setkube"
alias r="replicated"



if [[ ${PROFILE_NAME} == "Ubuntu" || 
      ${PROFILE_NAME} == "Development" ||
      ${PROFILE_NAME} == "replicated" ]]; then
   setkube global
else
   setkube ${PROFILE_NAME} 
fi
