# Google Swift Style Guide

This is the source for the
[Google Swift Style Guide](https://google.github.io/swift) website, which is
based on the [Swift.org](https://swift.org) documentation (found at
https://github.com/apple/swift-internals).

## Local Testing and Development

1. Have Ruby >= 2.0.0 installed.
2. `gem install bundler`—this command must normally be run with
   sudo/root/admin privileges.
3. `bundle install`—run this command as a regular, unprivileged user.
4. `LC_ALL=en_us.UTF-8 bundle exec jekyll serve --baseurl /swift-style`
5. Visit [http://localhost:4000/swift-style/](http://localhost:4000/swift-style/).
6. Make edits to the source, refresh your browser, lather, rinse, repeat.

Notes:

* Changes to `_config.yml` require restarting the local server (step 4
  above).
* If you make changes to `_config.yml` specifically in order to serve
  these pages from an address other than
  http://google.github.io/swift-style, please make sure those
  changes are not included in any pull requests, so we don't
  inadvertently break the main site.
