#pragma once

//
// StoreSQLiteShim.h — the one SQLite connection option the library store sets that Swift can't
// (S10.8 C2). `sqlite3_db_config` is a C VARIADIC function, which Swift does not import, and GRDB
// wraps only the options it uses itself. Pure C, no state.
//

#include <sqlite3.h>
#include <stdbool.h>

/// Stop SQLite checkpointing the WAL into the main database file when `connection` — the last one
/// to it — closes (`SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE`). The store's open path looks at an existing
/// library on such a connection first, so a library it REFUSES is left byte-identical even when a
/// crash left writes in its WAL. Returns whether SQLite accepted the option.
bool storeSQLiteDisableCheckpointOnClose(sqlite3* connection);
