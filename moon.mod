// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "hiroyannnn/yuru-poll"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/hiroyannnn/yuru-poll"

license = "Apache-2.0"

keywords = [ "jev", "typesafe", "poll", "survey", "live-chat", "streaming" ]

preferred_target = "native"

description = "Loose polling: free-text comments become fractional votes via TypeSafe Jev (System One)"

import {
  "moonbitlang/async@0.22.1",
  "hiroyannnn/yuru-kit@0.1.0",
}
