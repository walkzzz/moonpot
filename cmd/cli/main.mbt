/// Entry point for the MoonPot CLI. Real arguments come from the OS
/// (`@env.args()`); under `moonrun` with no args it falls back to `help`.
fn main {
  let args = @env.args()
  let exit_code = @mcli.run_cli(args)
  if exit_code != 0 {
    // Signal failure to the host without raising.
    println("exit: " + exit_code.to_string())
  }
}
