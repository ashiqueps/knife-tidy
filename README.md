# knife tidy

# Summary

This Chef Knife plugin provides:
 * Reports on the state of Chef Server objects that can be tidied up
 * Removal of stale nodes (and associated clients and ACLs) identified by the above Reports
 * A [knife-ec-backup](https://github.com/chef/knife-ec-backup) companion tool that will clean up data integrity issues in an object backup

# Requirements

A current Chef Client. Can easily be installed via [Chef DK](https://github.com/chef/chef-dk#installation)

# Installation

Via Rubygems
```bash
gem install knife-tidy
```

Via Source
```bash
git clone https://github.com/chef-customers/knife-tidy.git
cd knife-tidy
gem build knife-tidy.gemspec && gem install knife-tidy-*.gem --no-ri --no-rdoc
```

## Common Options

The following options are supported across all subcommands:

  * `--orgs ORG1,ORG2`:
    Only apply to objects in the named organizations (default: all orgs)

## $ knife tidy server report --help

Cookbooks and nodes account for the largest objects in your Chef Server.
If you want to keep it lean and mean and easy to port the object data, you must
tidy these unused objects up!

## Options

  * `--node-threshold NUM_DAYS`
    Maximum number of days since last checkin before node is considered stale (default: 30)

Example:
```bash
knife tidy server report --orgs brewinc,acmeinc --node-threshold 50
```

## Notes
  `server report` generates json reports as such:

File Name | Contents
--- | ---
org_threshold_numdays_stale_nodes.json | Nodes in that org that have not checked in for the number of days specified.
org_cookbook_count.json | Number of cookbook versions for each cookbook that that org.
org_unused_cookbooks.json | List of cookbooks and versions that do not appear to be in-use for that org. This is determined by checking the versioned run list of each of the nodes in the org.

## $ knife tidy server clean --help
Remove stale nodes that haven't checked-in to the Chef Server as defined by the `--node-threshold NUM_DAYS` option when the reports were generated.. The associated client and ACLs are also removed.

Future: remove unused cookbooks - currently this feature is disabled.

## Options

  * `--dry-run`
    Do not perform any actual deletion, only report on what would have been deleted.

Example:
```bash
knife tidy server clean --orgs brewinc,acmeinc
```

## $ knife tidy backup clean --help

## Options

  * `--backup-path /path/to/an-ec-backup`:
    The Chef Repo to tidy up (such as one created from a [knife-ec-backup](https://github.com/chef/knife-ec-backup)

  * `--gsub-file /path/to/gsub/file`:
    The path to the file used for substitutions. If non-existant, a boiler plate one will be created.

Run the following example before attempting the `knife ec backup restore` operation:
```bash
knife tidy backup clean --gen-gsub
INFO: Creating boiler plate gsub file: 'substitutions.json'
knife tidy backup clean --backup-path backups/ --gsub-file substitutions.json
```

## Notes

  Global file substitutions can be performed when `--gsub-file` option is used. Several known issues are corrected
  and others can be added with search/replace pairings. The following boiler plate file is created for you when `--gen-gsub` is used:

```json
{
  "io-read-version-and-readme.md":{
    "organizations/*/cookbooks/*/metadata.rb":[
      {
        "pattern":"^version +IO.read.* 'VERSION'.*",
        "replace":"version !COOKBOOK_VERSION!"
      },
      {
        "pattern":"^long_description +IO.read.* 'README.md'.*",
        "replace":"#long_description \"A Long Description..\""
      }
    ]
  }
}
```

## Summary and Credits

  * Server Report was ported from Nolan Davidson's [chef-cleanup](https://github.com/nsdavidson/chef-cleanup)
