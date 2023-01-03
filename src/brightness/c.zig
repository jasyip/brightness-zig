const c = @cImport({
    @cInclude("mpdecimal.h");
});
pub usingnamespace c;


pub fn mpdNewZ() !*c.mpd_t {
    const output = c.mpd_qnew();
    return if (@ptrToInt(output) == 0) error.MPD_Malloc_error else output;
}
