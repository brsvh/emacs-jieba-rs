use emacs::{CallEnv, Env, Result};

emacs::plugin_is_GPL_compatible!();

fn hello(env: &CallEnv) -> Result<()> {
    env.message("Hello from jieba-rs!")?;
    Ok(())
}

#[emacs::module(name(fn))]
fn init(env: &Env) -> Result<()> {
    emacs::__export_functions! {
        env, "jieba-rs-", {
            "hello" => (hello, 0..0, "Greet from jieba-rs"),
        }
    }
    Ok(())
}
