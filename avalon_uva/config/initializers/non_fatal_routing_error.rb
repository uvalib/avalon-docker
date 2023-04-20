# This initializer changes the log level of RoutingErrors to 'warn' (so they still appear in logs but are not fatal)
# this means we can use logging notifications on eg. >= error without all the false positives
# ref: https://stackoverflow.com/questions/9108565/rails-how-to-change-log-level-for-actioncontrollerroutingerror
module ActionDispatch
  class DebugExceptions
    alias_method :old_log_error, :log_error
    def log_error(request, wrapper)
      if wrapper.exception.is_a?  ActionController::RoutingError
        # Full message eg. "[404] ActionController::RoutingError (No route matches [GET] \"/wp-login.php\")"
        logger(request).send(:warn, "[404] ActionController::RoutingError (#{wrapper.exception.message})")
        return
      else
        old_log_error request, wrapper
      end
    end
  end
end
