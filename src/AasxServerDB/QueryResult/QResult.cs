using AasxServerDB.Result;

namespace AasxServerDB
{
    public class QResult
    {
        public List<string> Messages { get; set; }

        public List<SMResult> SMResults { get; set; }
        public List<SMEResult> SMEResults { get; set; }
    }
}
