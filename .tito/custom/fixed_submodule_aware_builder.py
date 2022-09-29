import os

from tito.builder import SubmoduleAwareBuilder as BuggySubmoduleAwareBuilder
from tito.common import (
    chdir,
    debug,
    run_command,
    create_tgz,
    get_commit_timestamp,
)
from tito.tar import TarFixer


class SubmoduleAwareBuilder(BuggySubmoduleAwareBuilder):
    def run_git_archive(self, relative_git_dir, prefix, commit, dest_tar, subdir=None):
        # command to generate a git-archive
        git_archive_cmd = "git archive --format=tar --prefix=%s/ %s:%s --output=%s" % (
            prefix,
            commit,
            relative_git_dir,
            dest_tar,
        )

        if subdir is None:
            return run_command(git_archive_cmd)

        with chdir(subdir):
            run_command(git_archive_cmd)

            # Run git-archive separately if --debug was specified.
            # This allows us to detect failure early.
            # On git < 1.7.4-rc0, `git archive ... commit:./` fails!
            debug(
                "git-archive fails if relative dir is not in git tree",
                "%s > /dev/null" % git_archive_cmd,
            )

    def create_tgz(self, git_root, prefix, commit, relative_dir, dest_tgz):
        """
        Create a .tar.gz from a projects source in git.
        And include submodules
        """

        git_root_abspath = os.path.abspath(git_root)
        gitmodules_path = os.path.join(git_root_abspath, ".gitmodules")

        # if .gitmodules does not exist, just call the existing create_tgz function
        # as there is nothing to see here.
        if not os.path.exists(gitmodules_path):
            return create_tgz(git_root, prefix, commit, relative_dir, dest_tgz)

        os.chdir(git_root_abspath)
        timestamp = get_commit_timestamp(commit)

        # Accommodate standalone projects with specfile in root of git repo:
        relative_git_dir = "%s" % relative_dir
        if relative_git_dir in ["/", "./"]:
            relative_git_dir = ""

        basename = os.path.splitext(dest_tgz)[0]
        initial_tar = "%s.initial" % basename

        # We need to tar up the following:
        # 1. the current repo
        self.run_git_archive(relative_git_dir, prefix, commit, initial_tar, None)

        # 2. all of the submodules
        # then combine those into a single archive.
        submodules_cmd = "git submodule--helper list"
        submodules_output = run_command(submodules_cmd)

        # split submodules output on newline
        # then on tab, and the directory is the last entry
        submodules_list = [
            line.split("\t")[-1] for line in submodules_output.split("\n")
        ]

        submodule_tar_files = []
        # We ignore the hash in the sub modules list as we'll have to get the correct one
        # from the commit id in commit
        for submodule in submodules_list:
            # to find the submodule shars:
            # git rev-parse <commit>:./<submodule>
            rev_parse_cmd = "git rev-parse %s:./%s" % (commit, submodule)
            submodule_commit = run_command(rev_parse_cmd)
            submodule_tar_file = "%s.%s" % (initial_tar, submodule.replace("/", "_"))
            # prefix should be <prefix>/<submodule>
            submodule_prefix = "%s/%s" % (prefix, submodule)

            self.run_git_archive(
                relative_git_dir,
                submodule_prefix,
                submodule_commit,
                submodule_tar_file,
                submodule,
            )
            submodule_tar_files.append(submodule_tar_file)

        # we need to append all of the submodule tar files onto the initial
        # Tar can concatenate only 2 archives at a time
        for tar_file in submodule_tar_files:
            run_command("tar -Af %s %s" % (initial_tar, tar_file))

        fixed_tar = "%s.tar" % basename
        fixed_tar_fh = open(fixed_tar, "wb")
        try:
            tarfixer = TarFixer(
                open(initial_tar, "rb"), fixed_tar_fh, timestamp, commit
            )
            tarfixer.fix()
        finally:
            fixed_tar_fh.close()

        # It's a pity we can't use Python's gzip, but it doesn't offer an equivalent of -n
        return run_command("gzip -n -c < %s > %s" % (fixed_tar, dest_tgz))
