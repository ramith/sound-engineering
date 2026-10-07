// StoreSQLiteShim.c — see include/StoreSQLiteShim.h.

#include "StoreSQLiteShim.h"

bool storeSQLiteDisableCheckpointOnClose(sqlite3* connection)
{
    int enabled = 0;
    const int result = sqlite3_db_config(connection, SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE, 1, &enabled);
    return result == SQLITE_OK && enabled == 1;
}
