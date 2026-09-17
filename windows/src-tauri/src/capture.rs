//! Capture ownership is independent of window focus and input delivery.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Source {
    Keyboard,
    Button,
}

pub struct Gate {
    owner: Option<Source>,
    held: bool,
}
impl Gate {
    pub const fn new() -> Self {
        Self {
            owner: None,
            held: false,
        }
    }
    pub fn busy(&self) -> bool {
        self.owner.is_some()
    }
    pub fn press(&mut self, source: Source) -> bool {
        if self.busy() {
            return false;
        }
        self.owner = Some(source);
        self.held = true;
        true
    }
    pub fn release(&mut self, source: Source) -> bool {
        if self.owner != Some(source) || !self.held {
            return false;
        }
        self.held = false;
        true
    }
    pub fn cancel(&mut self) -> bool {
        if !self.held {
            return false;
        }
        self.held = false;
        true
    }
    pub fn finish(&mut self) {
        self.owner = None;
        self.held = false;
    }
}

#[derive(Default)]
pub struct KeyEdges {
    down: bool,
    escape: bool,
}
#[derive(Debug, PartialEq)]
pub enum Edge {
    Press,
    Release,
    Cancel,
}
impl KeyEdges {
    pub fn update(&mut self, down: bool, escape: bool) -> Option<Edge> {
        let event = if escape && !self.escape {
            Some(Edge::Cancel)
        // A press is an edge on the trigger, whatever Escape is doing. Requiring Escape
        // to be up meant a key left held from an earlier cancel kept the trigger dead,
        // with nothing on screen saying why.
        } else if down && !self.down {
            Some(Edge::Press)
        } else if !down && self.down {
            Some(Edge::Release)
        } else {
            None
        };
        // Cancellation never synthesizes a release or rearms a still-held key.
        self.down = down;
        self.escape = escape;
        event
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cancel_requires_a_physical_release_before_another_press() {
        let mut keys = KeyEdges::default();
        assert_eq!(keys.update(true, false), Some(Edge::Press));
        assert_eq!(keys.update(true, true), Some(Edge::Cancel));
        for _ in 0..10 {
            assert_eq!(keys.update(true, true), None);
        }
        assert_eq!(keys.update(true, false), None);
        assert_eq!(keys.update(false, false), Some(Edge::Release));
        assert_eq!(keys.update(true, false), Some(Edge::Press));
    }
    #[test]
    fn a_held_escape_does_not_block_a_new_press() {
        let mut keys = KeyEdges::default();
        // Escape goes down with nothing held: it cancels nothing and stays down.
        assert_eq!(keys.update(false, true), Some(Edge::Cancel));
        assert_eq!(keys.update(true, true), Some(Edge::Press));
        assert_eq!(keys.update(false, true), Some(Edge::Release));
    }
    #[test]
    fn button_and_keyboard_cannot_release_each_other() {
        let mut g = Gate::new();
        assert!(g.press(Source::Button));
        assert!(!g.press(Source::Keyboard));
        assert!(!g.release(Source::Keyboard));
        assert!(g.release(Source::Button));
        assert!(g.busy());
        assert!(!g.press(Source::Keyboard));
        g.finish();
        assert!(g.press(Source::Keyboard));
    }
    #[test]
    fn cancelled_and_failed_runs_do_not_leave_a_stuck_gate() {
        let mut g = Gate::new();
        assert!(g.press(Source::Keyboard));
        assert!(g.cancel());
        assert!(!g.release(Source::Keyboard));
        assert!(!g.cancel());
        assert!(g.busy());
        g.finish();
        assert!(g.press(Source::Button));
        g.finish();
        assert!(!g.busy());
    }
}
