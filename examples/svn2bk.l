/*
 * This is a little SVN to BK importer written in L.
 *
 * It does not attempt to handle
 *	renames (other than copy/delete pretty much like SVN)
 *
 * -hHOST		set the hostname used for checkins
 * --host=host
 *
 * -i			incremental, import whatever has been added
 * --incremental
 *
 * -rstart		start at this commit in the svn repo (default 1)
 * -rstart..stop	set both starting and stopping points (default 1..HEAD)
 * -r..stop		stop at this one (default HEAD)
 *
 * --rcs		turn on RCS keyword expansion (untested)
 *			XXX - really want a way to s/$Id ... Exp $/$Id$/
 *
 * --verify		do an export and an extra checkout to verify contents
 * --use-externals	assume the SVN repository has externals and they are
 *			safe to use -- else use --ignore-externals
 *
 * Examples:
 *
 * Capture the early history:
 * $ svn2bk.l -r1..500 -hgoogle.com file:///svn/groogle/trunk groogle
 *
 * Now do the rest of the history:
 * $ cd groogle
 * $ svn2bk.l -hgoogle.com -i
 */

typedef struct {
	string	user;		// username who did the check in
	string	date;		// 2007-05-13 03:21:54 -0700
	string	cmts[];		// array of comments for the commit
} delta;

delta	log{int};		// cache of the entire log
int	revs[];			// ordered list of revs for this branch
string	q = "-q";		// -v turns this off and makes bk/svn noisy
int	debug = 0;		// debug
int	quiet = 0;
int	BAM = 0;		// --BAM option
int	force_binary = 0;	// --force-binary
string	ignore_ext = "--ignore-externals";
//string	nolog = "--no-log";  // bk --no-log has not yet shipped
string	nolog = "";

void
main(_argused int ac, string av[])
{
	string	c, host = "svn2bk.arpa", url, dir;
	int	start = 0, stop = 0;	// if set, do this range.
	int	incremental = 0;	// if set, start from last stop
	int	branch = 0;		// if set, don't create a BK repo
	int	verify = 0;		// if set, verify each commit
	int	rcs = 0;
	int	i;
	string	leftovers = "0";
	string	lopts[] = {
		"BAM",
		"host:",
		"incremental",
		"rcs",
		"verify",
		"use-externals",
		"force-binary"
		};

	while (c = getopt(av, "bdh:iqr:v", lopts)) {
		switch (c) {
		    case "b":
			branch = 1;
			break;
		    case "d":
			debug++;
			break;
		    case "h":
		    case "host":
			host = optarg;
			break;
		    case "i":
		    case "incremental":
			incremental = 1;
			break;
		    case "q":
			quiet = 1;
			break;
		    case "r":
			if (optarg =~ /(.+)\.\.(.+)/) {
				start = (int)$1;
				stop = (int)$2;
			} else if (optarg =~ /^\.\.(.+)/) {
				stop = (int)$1;
			} else {
				start = (int)optarg;
			}
			break;
		    case "rcs":
			rcs = 1;
			break;
		    case "v": q = ""; break;
		    case "verify": verify = 1; break;
		    case "BAM": BAM = 1; break;
		    case "use-externals": ignore_ext = ""; break;
		    case "force-binary": force_binary = 1; break;
		    default:
			fprintf(stderr, "Unknown option: %s\n", av[optind]);
			usage();
		}
	}
	url = av[optind++];
	dir = av[optind];

	// To run our blessed regressions, need to quote spaces
	url =~ s/ /\\ /g;

	unless (start) start = 1;
	putenv("BK_HOST=%s", host);
	unless ((url && dir) || incremental) usage();
	if (incremental) {
		unless (isdir(".bk") && isdir(".svn")) {
			die("Not at a BK/SVN root\n");
		}
		url = `cat BitKeeper/log/svn_url`;
		env();
		leftovers=String_trimleft(`bk ${nolog} -cxpU | wc -l`);
		unless (leftovers == "0") {
			die("Uncommitted, pending, or extra files, "
			    "please run citool");
		}
	} else if (setup(start, url, dir, rcs, branch)) {
		die("Failed to setup the SVN/BK repository");
	}
	if (getlog(url, incremental, ++start, stop)) {
		die("Failed to get the svn log");
	}
	for (i = 0; defined(revs[i]); i++) {
		assert(cset(revs[i], verify, url) == 0);
		unless (quiet) {
			printf("%d of %d complete\n",
			    revs[i], revs[length(revs)-1]);
		}
	}
	sys("bk ${nolog} -r admin -Z");
	if (quiet) {
		sys("bk ${nolog} repocheck ${q}");
	} else {
		sys("bk ${nolog} repocheck");
	}
}

/*
 * Create an empty bk repo and the intial svn repo
 * We want to end up with .bk next to .svn
 */
int
setup(int start, string url, string dir, int rcs, int branch)
{
	string	buf, codir = dir;
	FILE	f;
	int	rev;

	for (rev = start; rev > 0; rev--) {
		buf = `svn log -r${rev} ${url}`;
		unless (stdio_status.path) {
			die("svn doesn't appear to be installed");
		}
		if (buf =~ /[^-]/) break;
	}
	unless (start == rev) {
		die("%d is not active in this branch.  Try %d?\n", start, rev);
	}
	unless (quiet) fprintf(stderr, "### SVN ${start} ###\n");

	if (branch) {
		unless (chdir(dir) == 0) {
			die("cannot chdir to ${dir}");
		}
		unless (isdir(".bk")) {
			die("doesn't appear to be a a BK repo");
		}
		// May fail, shut up about it
		system("bk ${nolog} -U edit -q");
		sys("bk ${nolog} -Ug | xargs rm -f");
		// May fail, shut up and carry on
		system("bk ${nolog} find . -depth -type d | grep -v '^\.\/BitKeeper' | " .
		    "grep -v '^\.\/\.bk' | grep -v '^\.$' | "
		    "xargs rmdir 2>/dev/null");
		codir = ".";
	}
	unless (sys("svn co ${q} -r${start} ${url} ${codir}") == 0) {
		return (1);
	}
	chdir(codir);

	unless (branch) {
		/*
		 * Set up a repo inside the svn repo
		 * Use a hash of the log entry as random bits, alg from mdbm/hash.c
		 * limited to 64 bits.
		 */
		putenv("BK_DATE_TIME_ZONE=1970-01-01 01:00:00-0");
		putenv("BK_USER=svn2bk");
		putenv("BK_RANDOM=cons");
		f = fopen(".bk_config", "w");
		fprintf(f, "checkout:edit\n");
		fprintf(f, "clock_skew:on\n");
		fprintf(f, "partial_check:on\n");
		if (BAM) {
			if (force_binary) {
				fprintf(f, "BAM:1!\n");
			} else {
				fprintf(f, "BAM:on!\n");
			}
		}
		if (rcs) fprintf(f, "keyword:rcs\n");
		fclose(f);

		if (sys("bk ${nolog} setup -a -e -fc.bk_config .")) {
			fprintf(stderr, "bk setup failed\n");
			return (1);
		}
		unlink(".bk_config");

		// Prune the top level one, we'll grep out the others
		sys("bk ${nolog} ignore '*/.svn -prune'");
	}

	// save the url for incrementals
	f = fopen("BitKeeper/log/svn_url", "w");
	fprintf(f, "%s\n", url);
	fclose(f);
	env();

	sys("bk ${nolog} -Ucx ci ${q} -aly'SVN ${start}'");
	sys("bk ${nolog} _eula -a");
	sys("bk ${nolog} commit ${q} -y'SVN ${start}'");
	unless (quiet) sys("bk ${nolog} root");
	sys("bk ${nolog} sane");
	return (0);
}

void
env(void)
{
	string	svn;

	//putenv("_BK_NO_UNIQ=YES");
	putenv("BK_CONFIG=clock_skew=2!;compression:none!;checkout:none!;sync:off!");
	putenv("CLOCK_DRIFT=1");
	putenv("_BK_CREATE_MISSING_DIRS=yes");
	svn = "SVN_I_LOVE_CORRUPTED_WORKING_COPIES_SO_DISABLE_SLEEP_FOR_TIMESTAMPS";
	putenv("${svn}=yes");
}

/*
 * Import a SVN commit.
 * We get the updates, then
 * - for each file that is not checked out, svn deleted it so we delete it
 * - for each modified/extra we check those in with the comment/user/date
 *   from the log message.
 */
int
cset(int rev, int verify, string url)
{
	FILE	f;
	string	buf, tmp, svn, bk, out, err, out2[], err2[];
	int	first, empty, dangling, recurs;

	unless (quiet) fprintf(stderr, "### SVN ${rev} ###\n");
	unless (sys("svn switch ${ignore_ext} ${q} -r${rev} ${url}") == 0) {
		return (1);
	}
	tmp = "BitKeeper/tmp/comments";
	f = fopen(tmp, "w");
	foreach (buf in log{rev}.cmts) {
		fprintf(f, "%s\n", buf);
	}
	fclose(f);
	putenv("BK_RANDOM=cons");
	/* filter weird stuff seen in the wild */
	log{rev}.user =~ s/@/-AT-/;
	putenv("BK_USER=%s", log{rev}.user);
	putenv("BK_DATE_TIME_ZONE=%s", log{rev}.date);
	system("bk -U^G ${nolog} rm -f");
	if (force_binary) {
		system("bk ${nolog} -Ux new ${q} -b -Y${tmp}");
	}
	if (system("bk ${nolog} -Ucx ci ${q} -alY${tmp}",
		undef, &out2, &err2)) {
		string	e;
		int	errors = 0;

		foreach (e in err2) {
			if (e =~ /(.*): file format is ascii, delta is binary./) {
				if (debug) {
					fprintf(stderr, "FIXING: %s\n", $1);
				}
				/* changed mode, just remove/re-add */
				sys("bk ${nolog} unedit -q '${$1}'");
				system("bk ${nolog} rm -f '${$1}'");
				sys("svn update ${q} -r${rev} ${$1}");
				sys("bk ${nolog} ci -qalY${tmp} '${$1}'");
			} else {
				if (debug) {
					fprintf(stderr, "NO MATCH: ${e}\n");
				}
				errors++;
			}
		}
		if (errors) {
			fprintf(stderr,
			    "bk ci ...  failed\n");
			return (1);
		}
	}
	f = fopen(tmp, "a");
	fprintf(f, "SVN: %d\n", rev);
	fclose(f);
	unless (system("bk ${nolog} commit ${q} --import -Y${tmp}") == 0) {
		return (1);
	}

	// XXX - For debugging, probably should be removed
	if (exists(".svn/tmp/svn2bk-STOP")) {
		fprintf(stderr,
		    "Stopped at user request, you can resume at %d\n", rev);
		return (1);
	}

	unless (verify) return (0);

	svn = sprintf("BitKeeper/tmp/svn.%d", getpid());
	sys("/bin/rm -rf ${svn}");
	unless (sys("svn co ${q} ${ignore_ext} -r${rev} ${url} ${svn}") == 0) {
		die("unable to check out ${rev} in ${svn}");
	}
	bk = sprintf("BitKeeper/tmp/bk.%d", getpid());
	sys("/bin/rm -rf ${bk}");
	unless (sys("bk export -r+ -tplain . ${bk}") == 0) {
		die("unable to export to ${bk}");
	}

	first = 1;
	empty = dangling = recurs = 0;
again:	system("bk ${nolog} diff -r --ignore-trailing-cr --exclude=.svn ${svn} ${bk}", undef, &out, &err);
	out .= err;
	undef(err);
	foreach (buf in split(/\n/, out)) {
		if (buf =~ m|^\?\? \.bk/$|) continue;
		if (buf =~ m|^\?\? BitKeeper/|) continue;
		if (buf =~ m| D BitKeeper/|) continue;
		// empty dirs w/ .svn crud don't count
		// XXX - not a perfect regexp, will blow chunks on :
		if (buf =~ m|Only in (${svn}.*): (.*)|) {
			tmp = `find '${$1}/${$2}' -type f | grep -v '/\.svn/'`;
			unless (length(tmp)) {
				empty++;
				continue;
			}
		}

		// dangling links don't count
		else if (buf =~ m|diff: (.*): No such file or directory|) {
			if (islink($1)) {
				dangling++;
				continue;
			}
		}

		// nor do recursive links.
		// remove them all and retry.
		else if (buf =~ m|diff: (.*): Too many levels of symbolic li|) {
			if (first) {
				unlink($1);
				recurs++;
			}
		}
		err .= buf;
		err .= "\n";
	}
	if (first && recurs) {
		first = 0;
		goto again;
	}
	if (length(err)) die(err);
	sys("/bin/rm -rf ${svn} ${bk}");

	if (empty) fprintf(stderr, "Ignored %d empty directories\n", empty);
	if (dangling) fprintf(stderr, "Ignored %d dangling links\n", dangling);
	if (recurs) fprintf(stderr, "Ignored %d recursive links\n", recurs);

	return (0);
}

/*
 * Load up the log, we'll use it for our commits.
 *	------------------------------------------------------------------------
 *	r59 | mcccol | 2007-04-17 18:23:39 -0700 (Tue, 17 Apr 2007) | 4 lines
 *	
 *	removed logging, started using Debug.error
 *	
 *	------------------------------------------------------------------------
 *	r60 | mcccol | 2007-04-17 18:25:08 -0700 (Tue, 17 Apr 2007) | 4 lines
 *	
 *	* Added fixbad to utf8 to repair damaged utf8
 *	* made regexps variables to preserver their regexp intrep
 *
 * etc.
 */
int
getlog(string url, int incremental, int start, int stop)
{
	FILE	f;
	int	rev;
	string	cmts[];
	string	buf, buf2;
	string	last_date = "";

	if (incremental) {
		start = (int)`svn info | grep Revision: | awk '{print $NF}'`;
		start++;
	}
	if (stop) {
		if (stop <= start) die("Already up to or past %d\n", stop);
		f = popen("svn log -r${start}:${stop} ${url}", "r");
	} else {
		// XXX: other ways to know if start doesn't exist?
		f = popen("svn log -r${start}:HEAD ${url} 2> /dev/null", "r");
	}
	unless ((buf = <f>) && (buf =~ /^[-]+$/)) {
done:		unless (quiet) {
			fprintf(stderr, "Seems like you are up to date.\n");
		}
		return (0);
	}

	for (buf = <f>; defined(buf); ) {
		if (buf =~ /\(no author\)/) buf =~ s/.no author./anon/;
		if (buf =~ /\(no date\)/) buf =~ s/.no date./${last_date}/;
		unless (buf =~ /^r(\d+) \| ([^|]+) \| ([0-9 :\-+]+) /) {
			die("expected rev/date: ${buf}\n");
		}
		rev = (int)$1;
		push(&revs, rev);
		log{rev}.user = (string)$2;
		last_date = log{rev}.date = (string)$3;
		buf = <f>;	// toss the blank line
		undef(cmts);	// toss previous comments
		for (buf = <f>, buf2 = <f>; defined(buf); ) {
			if ((length(buf) == 72) &&
			    (buf =~ /^[-]+$/) &&
			    (buf2 =~ /^r\d+ \| /) ||
			    !defined(buf2)) {
				break;
			}
			// strip out non-printables or ci will choke on them
			buf =~ s/[^[:print:]]+//g;
			push(&cmts, buf);
			buf = buf2;
			buf2 = <f>;
		}

		/*
		 * Lose trailing blank lines, they serve no purpose.
		 * But bk doesn't like empty comments files so add something.
		 */
		while (cmts[END] =~ /^\s*$/) pop(&cmts);
		unless (defined(cmts[0])) cmts[0] = "(no comments)";
		log{rev}.cmts = cmts;
		buf = buf2;
	}
	pclose(f);
	unless (length(revs)) goto done;
	return (0);
}

void
usage()
{
	die("usage: svn2bk <URL> <dest>.\n");
}

int
sys(string command)
{
	int	rc = system(command);

	if (rc) fprintf(stderr, "%s = %d\n", command, rc);
	return (rc);
}
