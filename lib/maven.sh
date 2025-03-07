#!/usr/bin/env bash

_mvn_java_opts() {
	local scope=${1}
	local home=${2}
	local cache=${3}

	echo -n "-Xmx1024m"
	if [ "$scope" = "compile" ]; then
		echo -n " $MAVEN_JAVA_OPTS"
	elif [ "$scope" = "test-compile" ]; then
		echo -n ""
	fi

	echo -n " -Duser.home=$home -Dmaven.repo.local=$cache/.m2/repository"
}

_mvn_cmd_opts() {
	local scope=${1}

	if [ "$scope" = "compile" ]; then
		echo -n "${MAVEN_CUSTOM_OPTS:-"-DskipTests"}"
		echo -n " ${MAVEN_CUSTOM_GOALS:-"clean dependency:list install"}"
	elif [ "$scope" = "test-compile" ]; then
		echo -n "${MAVEN_CUSTOM_GOALS:-"clean dependency:resolve-plugins test-compile"}"
	else
		echo -n ""
	fi
}

_mvn_settings_opt() {
	local home="${1}"
	local mavenInstallDir="${2}"

	if [ -n "$MAVEN_SETTINGS_PATH" ]; then
		echo -n "-s $MAVEN_SETTINGS_PATH"
	elif [ -n "$MAVEN_SETTINGS_URL" ]; then
		local settingsXml="${mavenInstallDir}/.m2/settings.xml"
		mkdir -p "$(dirname "${settingsXml}")"
		curl --retry 3 --retry-connrefused --connect-timeout 5 --silent --max-time 10 --location "${MAVEN_SETTINGS_URL}" --output "${settingsXml}"
		if [ -f "${settingsXml}" ]; then
			echo -n "-s ${settingsXml}"
		else
			error "Could not download settings.xml from the URL defined in MAVEN_SETTINGS_URL!"
			return 1
		fi
	elif [ -f "${home}/settings.xml" ]; then
		echo -n "-s ${home}/settings.xml"
	else
		echo -n ""
	fi
}

has_maven_wrapper() {
	local home=${1}
	if [ -f "${home}/mvnw" ] &&
		[ -f "${home}/.mvn/wrapper/maven-wrapper.properties" ] &&
		[ -z "$(detect_maven_version "${home}")" ]; then
		return 0
	else
		return 1
	fi
}

get_cache_status() {
	local cacheDir=${1}
	if [ ! -d "${cacheDir}/.m2" ]; then
		echo "not-found"
	else
		echo "valid"
	fi
}

run_mvn() {
	local scope=${1}
	local home=${2}
	local mavenInstallDir=${3}

	mkdir -p "${mavenInstallDir}"
	if has_maven_wrapper "${home}"; then
		cache_copy ".m2/wrapper" "${mavenInstallDir}" "${home}"
		chmod +x "${home}/mvnw"
		local mavenExe="./mvnw"
	else
		# shellcheck disable=SC2164
		cd "${mavenInstallDir}"

		install_maven "${mavenInstallDir}" "${home}"
		PATH="${mavenInstallDir}/.maven/bin:$PATH"
		local mavenExe="mvn"
		# shellcheck disable=SC2164
		cd "${home}"
	fi

	local mvn_settings_opt
	mvn_settings_opt="$(_mvn_settings_opt "${home}" "${mavenInstallDir}")"

	MAVEN_OPTS="$(_mvn_java_opts "${scope}" "${home}" "${mavenInstallDir}")"
	export MAVEN_OPTS

	# shellcheck disable=SC2164
	cd "${home}"
	local mvnOpts
	mvnOpts="$(_mvn_cmd_opts "${scope}")"

	status "Executing Maven"
	echo "$ ${mavenExe} ${mvnOpts}" | indent

	# We rely on word splitting for mvn_settings_opt and mvnOpts:
	# shellcheck disable=SC2086
	if ! ${mavenExe} -DoutputFile=target/mvn-dependency-list.log -B ${mvn_settings_opt} ${mvnOpts} | indent; then
		error "Failed to build app with Maven
We're sorry this build is failing! If you can't find the issue in application code,
please submit a ticket so we can help: https://help.heroku.com/"
	fi
}

write_mvn_profile() {
	local home
	home=${1}

	mkdir -p "${home}/.profile.d"
	cat <<-EOF >"${home}/.profile.d/maven.sh"
		export M2_HOME="\$HOME/.maven"
		export MAVEN_OPTS="$(_mvn_java_opts "test" "\$HOME" "\$HOME")"
		export PATH="\$M2_HOME/bin:\$PATH"
	EOF
}

remove_mvn() {
	local home=${1}
	local mavenInstallDir=${2}
	if has_maven_wrapper "${home}"; then
		cache_copy ".m2/wrapper" "$home" "$mavenInstallDir"
		rm -rf "$home/.m2"
	fi
}
