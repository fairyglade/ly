# Contributing to Ly

To contribute to Ly, you have to open a pull request on [Codeberg](https://codeberg.org/fairyglade/ly), as [GitHub](https://github.com/fairyglade/ly) is just a mirror. However, you also have to respect the following rules, otherwise your PR may end up being rejected:

## AI usage

While we cannot control your usage of any LLM whatsoever, we do heavily discourage their use for environmental, ethical & moral reasons that you can learn more about on the Internet. However, if you do end up still using them, here are a couple rules you **must absolutely** respect for your PR not to get instantly shot down. Of course, it goes without saying that **all** the other rules in the other sections below **must** be adhered to, even more so when AI is used.

1. **Communicate through you**, not the AI; as in, responses to reviews or other comments in the PR must be written by you and not an LLM. If English isn't your native language and you have a lot of trouble speaking it, you _may_ use AI, but responses must not be your typical, alienating AI-generated text: https://github.com/realrossmanngroup/no_ai_slop_writing_rules
2. Control the code, as in, **don't vibecode**, especially if you don't know Zig. Don't waste the maintainers's time, and **heavily test your code**, as AI-generated code is typically more error-prone in subtle ways (even if they can be better than humans in some other aspects). Finally, don't generate any "summary" or whatever the AI may come up with during the process. **If you cannot understand the generated code, do not contribute it**. Maintainers are busy and are often simple volunteers, so the less work they have to do, the better.
3. **Be transparent about AI usage**. Precise what AI model was used in the process, and preferably, how you went about creating your changes (i.e. how did you use AI to make the pull request). The more honest you are about it, the more likely your PR will be accepted and merged into the code base.

If all the above rules are respected, your changes have much more likely to be accepted into the code base.

## Code style

You must follow Zig's [style guide](https://ziglang.org/documentation/master/#Style-Guide). In most cases, all you'll have to do is run `zig fmt` after you have completed your changes, though it does not fix everything, notably variable, function & field naming, as well as the maximum length of aline.

For the former, please refer to the aforementioned style guide in that case. For the latter, you must respect a maximum line length of **80 characters**. For function calls with many parameters or anything similar that may overflow this limit, consider adding a trailing comma to the list so that `zig fmt` can split it into multiple lines. Ideally, few or no lines end up having to get soft wrapped by an editor having this limit set.

## Commit names & descriptions

1. **Commit names must be descriptive**, resorting to the commit description if they are too long. In such cases, the commit name **must** be shortened while still making sense. With that said, no particular convention (emojis, prefixes & suffixes, etc.) is mandated for them, and you are free to adopt any one you think is best or that you are used to.
2. **Do not force push**, as PRs will get squashed into a single commit anyway. This erases history and makes it impossible to see the changes done over time and by a particular commit.
3. While not a requirement per se, **consider signing your commits** with an SSH or GPG key for security purposes. This ensures to a lesser extent that you are the person who you claim to be, and reduces the potential amount of malicious contributions that could infiltrate the code base.

## Additional requirements

Other requirements (such as testing your code) for merging the changes will be available when you open your pull request via the template (which you **must** use), however, these are not stated here because they may not be mandatory in some cases (e.g. if the changes are still work-in-progress), so they may temporarily be ommitted for a certain period of time until the changes are fully ready to be reviewed, for instance.
