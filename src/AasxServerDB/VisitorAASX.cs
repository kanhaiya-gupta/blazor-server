/********************************************************************************
* Copyright (c) {2019 - 2024} Contributors to the Eclipse Foundation
*
* See the NOTICE file(s) distributed with this work for additional
* information regarding copyright ownership.
*
* This program and the accompanying materials are made available under the
* terms of the Apache License Version 2.0 which is available at
* https://www.apache.org/licenses/LICENSE-2.0
*
* SPDX-License-Identifier: Apache-2.0
********************************************************************************/

namespace AasxServerDB
{
    using AasCore.Aas3_0;
    using AdminShellNS;
    using static AasCore.Aas3_0.Visitation;
    using Extensions;
    using System.IO.Compression;
    using Microsoft.IdentityModel.Tokens;
    using AasxServerDB.Entities;
    using System.Text;
    using System.Collections.Generic;

    public class VisitorAASX : VisitorThrough
    {
        private EnvSet _envDB;
        private SMSet? _smDB;
        private SMESet? _parSME;
        private static Dictionary<string, int> _cdDBId = new Dictionary<string, int>();
        private string _oprPrefix = string.Empty;
        public const string OPERATION_INPUT = "In";
        public const string OPERATION_OUTPUT = "Out";
        public const string OPERATION_INOUTPUT = "IO";
        public const string OPERATION_SPLIT = "-";

        public VisitorAASX(EnvSet envDB)
        {
            _envDB = envDB;
        }





        // Load AASX
        public static void LoadAASXInDB(string filePath, bool createFilesOnly, bool withDbFiles)
        {
            using (var asp = new AdminShellPackageEnv(filePath, false, true))
            {
                if (!createFilesOnly)
                {
                    var envDB = new EnvSet() { Path = filePath };
                    LoadAASInDB(asp, envDB);

                    var db = new AasContext();
                    db.Add(envDB);
                    db.SaveChanges();

                    // CD
                    foreach (var envcdSet in envDB.EnvCDSets.Where(envcdSet => envcdSet.CDSet != null))
                        _cdDBId.TryAdd(envcdSet.CDSet.Identifier, envcdSet.CDSet.Id);
                }

                if (withDbFiles)
                {
                    var name = Path.GetFileName(filePath);
                    try
                    {
                        var temporaryFileName = name + "__thumbnail";
                        temporaryFileName = temporaryFileName.Replace("/", "_");
                        temporaryFileName = temporaryFileName.Replace(".", "_");
                        Uri? dummy = null;
                        using (var st = asp.GetLocalThumbnailStream(ref dummy, init: true))
                        {
                            Console.WriteLine("Copy " + AasContext.DataPath + "/files/" + temporaryFileName + ".dat");
                            var fst = System.IO.File.Create(AasContext.DataPath + "/files/" + temporaryFileName + ".dat");
                            if (st != null)
                            {
                                st.CopyTo(fst);
                            }
                        }
                    }
                    catch { }

                    using (var fileStream = new FileStream(AasContext.DataPath + "/files/" + name + ".zip", FileMode.Create))
                    using (var archive = new ZipArchive(fileStream, ZipArchiveMode.Create))
                    {
                        var files = asp.GetListOfSupplementaryFiles();
                        foreach (var f in files)
                        {
                            try
                            {
                                using (var s = asp.GetLocalStreamFromPackage(f.Uri.OriginalString, init: true))
                                {
                                    var archiveFile = archive.CreateEntry(f.Uri.OriginalString);
                                    Console.WriteLine("Copy " + AasContext.DataPath + "/" + name + "/" + f.Uri.OriginalString);

                                    using var archiveStream = archiveFile.Open();
                                    s.CopyTo(archiveStream);
                                }
                            }
                            catch { }
                        }
                    }
                }
            }
        }

        public static void LoadAASInDB(AdminShellPackageEnv asp, EnvSet envDB)
        {
            if (envDB == null || asp == null || asp.AasEnv == null)
                return;

            // ConceptDescriptions
            if (asp.AasEnv.ConceptDescriptions != null)
            {
                foreach (var cd in asp.AasEnv.ConceptDescriptions)
                {
                    if (cd == null || cd.Id.IsNullOrEmpty())
                        continue;

                    if (_cdDBId.ContainsKey(cd.Id))
                    {
                        envDB.EnvCDSets.Add(new EnvCDSet() { EnvSet = envDB, CDId = _cdDBId[cd.Id] });
                        continue;
                    }
                    new VisitorAASX(envDB: envDB).Visit(cd);
                }
            }

            // dictionary to save connection between aas and sm
            var aasToSm = new Dictionary<string, AASSet?>();

            // AssetAdministrationShells
            if (asp.AasEnv.AssetAdministrationShells != null)
            {
                foreach (var aas in asp.AasEnv.AssetAdministrationShells)
                {
                    if (aas == null)
                        continue;

                    if (!aas.IdShort.IsNullOrEmpty() && aas.IdShort.ToLower().Contains("globalsecurity"))
                    {
                        if (aas.Submodels == null)
                            continue;

                        foreach (var refSm in aas.Submodels)
                            if (refSm.Keys != null && refSm.Keys.Count() > 0 && !refSm.Keys[0].Value.IsNullOrEmpty())
                                aasToSm.TryAdd(refSm.Keys[0].Value, null);

                        continue;
                    }

                    new VisitorAASX(envDB: envDB).Visit(aas);

                    if (aas.Submodels == null)
                        continue;

                    foreach (var refSm in aas.Submodels)
                        if (refSm.Keys != null && refSm.Keys.Count() > 0 && !refSm.Keys[0].Value.IsNullOrEmpty())
                            aasToSm.TryAdd(refSm.Keys[0].Value, envDB.AASSets.Last());
                }
            }

            // Submodels
            if (asp.AasEnv.Submodels != null)
            {
                foreach (var sm in asp.AasEnv.Submodels)
                {
                    if (sm == null)
                        continue;

                    var found = !sm.Id.IsNullOrEmpty() && aasToSm.ContainsKey(sm.Id);
                    var aas = found ? aasToSm[sm.Id] : null;
                    if (found && aas == null)
                        continue;

                    new VisitorAASX(envDB: envDB).Visit(sm);

                    envDB.SMSets.Last().AASSet = aas;
                }
            }
        }





        // ConceptDescription
        public override void VisitConceptDescription(IConceptDescription that)
        {
            var currentDataTime = DateTime.UtcNow;
            var cdDB = new CDSet()
            {
                IdShort                     = that.IdShort,
                DisplayName                 = AasContext.SerializeList(that.DisplayName),
                Category                    = that.Category,
                Description                 = AasContext.SerializeList(that.Description),
                Extensions                  = AasContext.SerializeList(that.Extensions),
                Identifier                  = that.Id,
                IsCaseOf                    = AasContext.SerializeList(that.IsCaseOf),
                EmbeddedDataSpecifications  = AasContext.SerializeList(that.EmbeddedDataSpecifications),
                Version                     = that.Administration?.Version,
                Revision                    = that.Administration?.Revision,
                Creator                     = AasContext.SerializeElement(that.Administration?.Creator),
                TemplateId                  = that.Administration?.TemplateId,
                AEmbeddedDataSpecifications = AasContext.SerializeList(that.Administration?.EmbeddedDataSpecifications),
                /*
                TimeStampCreate             = that.TimeStampCreate == default ? currentDataTime : that.TimeStampCreate,
                TimeStamp                   = that.TimeStamp       == default ? currentDataTime : that.TimeStamp,
                TimeStampTree               = that.TimeStampTree   == default ? currentDataTime : that.TimeStampTree,
                TimeStampDelete             = that.TimeStampDelete == default ? currentDataTime : that.TimeStampDelete
                */
                TimeStampCreate = that.TimeStampCreate,
                TimeStamp = that.TimeStamp,
                TimeStampTree = that.TimeStampTree,
                TimeStampDelete = that.TimeStampDelete
            };
            _envDB?.EnvCDSets.Add(new EnvCDSet() { EnvSet = _envDB, CDSet = cdDB });
            base.VisitConceptDescription(that);
        }

        // AssetAdministrationShell
        public override void VisitAssetAdministrationShell(IAssetAdministrationShell that)
        {
            var currentDataTime = DateTime.UtcNow;
            var aasDB = new AASSet()
            {
                IdShort                     = that.IdShort,
                DisplayName                 = AasContext.SerializeList(that.DisplayName),
                Category                    = that.Category,
                Description                 = AasContext.SerializeList(that.Description),
                Extensions                  = AasContext.SerializeList(that.Extensions),
                Identifier                  = that.Id,
                EmbeddedDataSpecifications  = AasContext.SerializeList(that.EmbeddedDataSpecifications),
                DerivedFrom                 = AasContext.SerializeElement(that.DerivedFrom),
                Version                     = that.Administration?.Version,
                Revision                    = that.Administration?.Revision,
                Creator                     = AasContext.SerializeElement(that.Administration?.Creator),
                TemplateId                  = that.Administration?.TemplateId,
                AEmbeddedDataSpecifications = AasContext.SerializeList(that.Administration?.EmbeddedDataSpecifications),
                AssetKind                   = AasContext.SerializeElement(that.AssetInformation?.AssetKind),
                SpecificAssetIds            = AasContext.SerializeList(that.AssetInformation?.SpecificAssetIds),
                GlobalAssetId               = that.AssetInformation?.GlobalAssetId,
                AssetType                   = that.AssetInformation?.AssetType,
                DefaultThumbnailPath        = that.AssetInformation?.DefaultThumbnail?.Path,
                DefaultThumbnailContentType = that.AssetInformation?.DefaultThumbnail?.ContentType,
                /*
                TimeStampCreate             = that.TimeStampCreate == default ? currentDataTime : that.TimeStampCreate,
                TimeStamp                   = that.TimeStamp       == default ? currentDataTime : that.TimeStamp,
                TimeStampTree               = that.TimeStampTree   == default ? currentDataTime : that.TimeStampTree,
                TimeStampDelete             = that.TimeStampDelete == default ? currentDataTime : that.TimeStampDelete
                */
                TimeStampCreate = that.TimeStampCreate,
                TimeStamp = that.TimeStamp,
                TimeStampTree = that.TimeStampTree,
                TimeStampDelete = that.TimeStampDelete
            };
            _envDB?.AASSets.Add(aasDB);
            base.VisitAssetAdministrationShell(that);
        }

        // Submodel
        public override void VisitSubmodel(ISubmodel that)
        {
            var currentDataTime = DateTime.UtcNow;
            _smDB = new SMSet()
            {
                IdShort                     = that.IdShort,
                DisplayName                 = AasContext.SerializeList(that.DisplayName),
                Category                    = that.Category,
                Description                 = AasContext.SerializeList(that.Description),
                Extensions                  = AasContext.SerializeList(that.Extensions),
                Identifier                  = that.Id,
                Kind                        = AasContext.SerializeElement(that.Kind),
                SemanticId                  = that.SemanticId?.GetAsIdentifier(),
                SupplementalSemanticIds     = AasContext.SerializeList(that.SupplementalSemanticIds),
                Qualifiers                  = AasContext.SerializeList(that.Qualifiers),
                EmbeddedDataSpecifications  = AasContext.SerializeList(that.EmbeddedDataSpecifications),
                Version                     = that.Administration?.Version,
                Revision                    = that.Administration?.Revision,
                Creator                     = AasContext.SerializeElement(that.Administration?.Creator),
                TemplateId                  = that.Administration?.TemplateId,
                AEmbeddedDataSpecifications = AasContext.SerializeList(that.Administration?.EmbeddedDataSpecifications),
                /*
                TimeStampCreate             = that.TimeStampCreate == default ? currentDataTime : that.TimeStampCreate,
                TimeStamp                   = that.TimeStamp       == default ? currentDataTime : that.TimeStamp,
                TimeStampTree               = that.TimeStampTree   == default ? currentDataTime : that.TimeStampTree,
                TimeStampDelete             = that.TimeStampDelete == default ? currentDataTime : that.TimeStampDelete
                */
                TimeStampCreate = that.TimeStampCreate,
                TimeStamp = that.TimeStamp,
                TimeStampTree = that.TimeStampTree,
                TimeStampDelete = that.TimeStampDelete
            };
            _envDB?.SMSets.Add(_smDB);
            base.VisitSubmodel(that);
        }





        // SubmodelElement
        private SMESet CreateSMESet(ISubmodelElement sme)
        {
            var currentDataTime = DateTime.UtcNow;
            var smeDB = new SMESet()
            {
                ParentSME                  = _parSME,
                SMEType                    = ShortSMEType(sme),
                IdShort                    = sme.IdShort,
                DisplayName                = AasContext.SerializeList(sme.DisplayName),
                Category                   = sme.Category,
                Description                = AasContext.SerializeList(sme.Description),
                Extensions                 = AasContext.SerializeList(sme.Extensions),
                SemanticId                 = sme.SemanticId?.GetAsIdentifier(),
                SupplementalSemanticIds    = AasContext.SerializeList(sme.SupplementalSemanticIds),
                Qualifiers                 = AasContext.SerializeList(sme.Qualifiers),
                EmbeddedDataSpecifications = AasContext.SerializeList(sme.EmbeddedDataSpecifications),
                /*
                TimeStampCreate            = sme.TimeStampCreate == default ? currentDataTime : sme.TimeStampCreate,
                TimeStamp                  = sme.TimeStamp       == default ? currentDataTime : sme.TimeStamp,
                TimeStampTree              = sme.TimeStampTree   == default ? currentDataTime : sme.TimeStampTree,
                TimeStampDelete            = sme.TimeStampDelete == default ? currentDataTime : sme.TimeStampDelete
                */
                TimeStampCreate = sme.TimeStampCreate,
                TimeStamp = sme.TimeStamp,
                TimeStampTree = sme.TimeStampTree,
                TimeStampDelete = sme.TimeStampDelete
            };
            SetValues(sme, smeDB);
            _smDB?.SMESets.Add(smeDB);
            return smeDB;
        }
        private string ShortSMEType(ISubmodelElement sme) => _oprPrefix + sme switch
        {
            RelationshipElement          => "Rel",
            AnnotatedRelationshipElement => "RelA",
            Property                     => "Prop",
            MultiLanguageProperty        => "MLP",
            Range                        => "Range",
            Blob                         => "Blob",
            File                         => "File",
            ReferenceElement             => "Ref",
            Capability                   => "Cap",
            SubmodelElementList          => "SML",
            SubmodelElementCollection    => "SMC",
            Entity                       => "Ent",
            BasicEventElement            => "Evt",
            Operation                    => "Opr",
            _                            => string.Empty
        };
        public static Dictionary<DataTypeDefXsd, string> DataTypeToTable = new Dictionary<DataTypeDefXsd, string>() {
            { DataTypeDefXsd.AnyUri, "S" },
            { DataTypeDefXsd.Base64Binary, "S" },
            { DataTypeDefXsd.Boolean, "S" },
            { DataTypeDefXsd.Byte, "I" },
            { DataTypeDefXsd.Date, "S" },
            { DataTypeDefXsd.DateTime, "S" },
            { DataTypeDefXsd.Decimal, "S" },
            { DataTypeDefXsd.Double, "D" },
            { DataTypeDefXsd.Duration, "S" },
            { DataTypeDefXsd.Float, "D" },
            { DataTypeDefXsd.GDay, "S" },
            { DataTypeDefXsd.GMonth, "S" },
            { DataTypeDefXsd.GMonthDay, "S" },
            { DataTypeDefXsd.GYear, "S" },
            { DataTypeDefXsd.GYearMonth, "S" },
            { DataTypeDefXsd.HexBinary, "S" },
            { DataTypeDefXsd.Int, "I" },
            { DataTypeDefXsd.Integer, "I" },
            { DataTypeDefXsd.Long, "I" },
            { DataTypeDefXsd.NegativeInteger, "I" },
            { DataTypeDefXsd.NonNegativeInteger, "I" },
            { DataTypeDefXsd.NonPositiveInteger, "I" },
            { DataTypeDefXsd.PositiveInteger, "I" },
            { DataTypeDefXsd.Short, "I" },
            { DataTypeDefXsd.String, "S" },
            { DataTypeDefXsd.Time, "S" },
            { DataTypeDefXsd.UnsignedByte, "I" },
            { DataTypeDefXsd.UnsignedInt, "I" },
            { DataTypeDefXsd.UnsignedLong, "I" },
            { DataTypeDefXsd.UnsignedShort, "I" }
        };
        private static bool GetValueAndDataType(string value, DataTypeDefXsd dataType, out string tableDataType, out string sValue, out long iValue, out double dValue)
        {
            tableDataType = DataTypeToTable[dataType];
            sValue = string.Empty;
            iValue = 0;
            dValue = 0;

            if (value.IsNullOrEmpty())
                return false;

            // correct table type
            switch (tableDataType)
            {
                case "S":
                    sValue = value;
                    return true;
                case "I":
                    if (Int64.TryParse(value, out iValue))
                        return true;
                    break;
                case "D":
                    if (Double.TryParse(value, out dValue))
                        return true;
                    break;
            }

            // incorrect table type
            if (Int64.TryParse(value, out iValue))
            {
                tableDataType = "I";
                return true;
            }

            if (Double.TryParse(value, out dValue))
            {
                tableDataType = "D";
                return true;
            }

            sValue = value;
            tableDataType = "S";
            return true;
        }
        private static void SetValues(ISubmodelElement sme, SMESet smeDB)
        {
            if (sme is RelationshipElement rel)
            {
                if (rel.First != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "First", Value = AasContext.SerializeElement(rel.First) });
                if (rel.Second != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "Second", Value = AasContext.SerializeElement(rel.Second) });
            }
            else if (sme is AnnotatedRelationshipElement relA)
            {
                if (relA.First != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "First", Value = AasContext.SerializeElement(relA.First) });
                if (relA.Second != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "Second", Value = AasContext.SerializeElement(relA.Second) });
            }
            else if (sme is Property prop)
            {
                if (prop.ValueId != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "ValueId", Value = AasContext.SerializeElement(prop.ValueId) });

                GetValueAndDataType(prop.Value ?? string.Empty, prop.ValueType, out var tValue, out var sValue, out var iValue, out var dValue);
                if (!tValue.IsNullOrEmpty())
                    smeDB.TValue = tValue;
                else
                    smeDB.TValue = "S";

                if (smeDB.TValue.Equals("S"))
                    smeDB.SValueSets.Add(new SValueSet { Value = sValue, Annotation = AasContext.SerializeElement(prop.ValueType) });
                else if (smeDB.TValue.Equals("I"))
                    smeDB.IValueSets.Add(new IValueSet { Value = iValue, Annotation = AasContext.SerializeElement(prop.ValueType) });
                else if (smeDB.TValue.Equals("D"))
                    smeDB.DValueSets.Add(new DValueSet { Value = dValue, Annotation = AasContext.SerializeElement(prop.ValueType) });
            }
            else if (sme is MultiLanguageProperty mlp)
            {
                if (mlp.ValueId != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "ValueId", Value = AasContext.SerializeElement(mlp.ValueId) });

                if (mlp.Value == null || mlp.Value.Count == 0)
                    return;

                smeDB.TValue = "S";
                foreach (var sValueMLP in mlp.Value)
                    if (!sValueMLP.Text.IsNullOrEmpty())
                        smeDB.SValueSets.Add(new SValueSet() { Annotation = sValueMLP.Language, Value = sValueMLP.Text });
            }
            else if (sme is Range range)
            {
                smeDB.OValueSets.Add(new OValueSet { Attribute = "ValueType", Value = AasContext.SerializeElement(range.ValueType) });

                if (range.Min.IsNullOrEmpty() && range.Max.IsNullOrEmpty())
                    return;

                var hasValueMin = GetValueAndDataType(range.Min ?? string.Empty, range.ValueType, out var tableDataTypeMin, out var sValueMin, out var iValueMin, out var dValueMin);
                var hasValueMax = GetValueAndDataType(range.Max ?? string.Empty, range.ValueType, out var tableDataTypeMax, out var sValueMax, out var iValueMax, out var dValueMax);

                // determine which data types apply
                var tableDataType = "S";
                if (!hasValueMin && !hasValueMax) // no value is given
                    return;
                else if (hasValueMin && !hasValueMax) // only min is given
                {
                    tableDataType = tableDataTypeMin;
                }
                else if (!hasValueMin && hasValueMax) // only max is given
                {
                    tableDataType = tableDataTypeMax;
                }
                else if (hasValueMin && hasValueMax) // both values are given
                {
                    if (tableDataTypeMin == tableDataTypeMax) // dataType did not change
                    {
                        tableDataType = tableDataTypeMin;
                    }
                    else if (!tableDataTypeMin.Equals("S") && !tableDataTypeMax.Equals("S")) // both a number
                    {
                        tableDataType = "D";
                        if (tableDataTypeMin.Equals("I"))
                            dValueMin = Convert.ToDouble(iValueMin);
                        else if (tableDataTypeMax.Equals("I"))
                            dValueMax = Convert.ToDouble(iValueMax);
                    }
                    else // default: save in string
                    {
                        tableDataType = "S";
                        if (!tableDataTypeMin.Equals("S"))
                            sValueMin = tableDataTypeMin.Equals("I") ? iValueMin.ToString() : dValueMin.ToString();
                        if (!tableDataTypeMax.Equals("S"))
                            sValueMax = tableDataTypeMax.Equals("I") ? iValueMax.ToString() : dValueMax.ToString();
                    }
                }

                smeDB.TValue = tableDataType.ToString();
                if (tableDataType.Equals("S"))
                {
                    if (hasValueMin)
                        smeDB.SValueSets.Add(new SValueSet { Value = sValueMin, Annotation = "Min" });
                    if (hasValueMax)
                        smeDB.SValueSets.Add(new SValueSet { Value = sValueMax, Annotation = "Max" });
                }
                else if (tableDataType.Equals("I"))
                {
                    if (hasValueMin)
                        smeDB.IValueSets.Add(new IValueSet { Value = iValueMin, Annotation = "Min" });
                    if (hasValueMax)
                        smeDB.IValueSets.Add(new IValueSet { Value = iValueMax, Annotation = "Max" });
                }
                else if (tableDataType.Equals("D"))
                {
                    if (hasValueMin)
                        smeDB.DValueSets.Add(new DValueSet { Value = dValueMin, Annotation = "Min" });
                    if (hasValueMax)
                        smeDB.DValueSets.Add(new DValueSet { Value = dValueMax, Annotation = "Max" });
                }
            }
            else if (sme is Blob blob)
            {
                if (blob.Value.IsNullOrEmpty() && blob.ContentType.IsNullOrEmpty())
                    return;

                smeDB.TValue = "S";
                smeDB.SValueSets.Add(new SValueSet { Value = blob.Value != null ? Encoding.ASCII.GetString(blob.Value) : string.Empty, Annotation = blob.ContentType });
            }
            else if (sme is File file)
            {
                if (file.Value.IsNullOrEmpty() && file.ContentType.IsNullOrEmpty())
                    return;

                smeDB.TValue = "S";
                smeDB.SValueSets.Add(new SValueSet { Value = file.Value, Annotation = file.ContentType });
            }
            else if (sme is ReferenceElement refEle)
            {
                if (refEle.Value != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "Value", Value = AasContext.SerializeElement(refEle.Value) });
            }
            else if (sme is SubmodelElementList sml)
            {
                if (sml.OrderRelevant != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "OrderRelevant", Value = AasContext.SerializeElement(sml.OrderRelevant) });

                if (sml.SemanticIdListElement != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "SemanticIdListElement", Value = AasContext.SerializeElement(sml.SemanticIdListElement) });

                smeDB.OValueSets.Add(new OValueSet { Attribute = "TypeValueListElement", Value = AasContext.SerializeElement(sml.TypeValueListElement) });

                if (sml.ValueTypeListElement != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "ValueTypeListElement", Value = AasContext.SerializeElement(sml.ValueTypeListElement) });
            }
            else if (sme is Entity ent)
            {
                smeDB.TValue = "S";
                smeDB.SValueSets.Add(new SValueSet { Value = ent.GlobalAssetId, Annotation = AasContext.SerializeElement(ent.EntityType) });

                if (ent.SpecificAssetIds != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "SpecificAssetIds", Value = AasContext.SerializeList(ent.SpecificAssetIds) });
            }
            else if (sme is BasicEventElement evt)
            {
                if (evt.Observed != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "Observed", Value = AasContext.SerializeElement(evt.Observed) });

                smeDB.OValueSets.Add(new OValueSet { Attribute = "Direction", Value = AasContext.SerializeElement(evt.Direction) });
                smeDB.OValueSets.Add(new OValueSet { Attribute = "State", Value = AasContext.SerializeElement(evt.State) });

                if (evt.MessageTopic != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "MessageTopic", Value = evt.MessageTopic });

                if (evt.MessageBroker != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "MessageBroker", Value = AasContext.SerializeElement(evt.MessageBroker) });

                if (evt.LastUpdate != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "LastUpdate", Value = evt.LastUpdate });

                if (evt.MinInterval != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "MinInterval", Value = evt.MinInterval });

                if (evt.MaxInterval != null)
                    smeDB.OValueSets.Add(new OValueSet { Attribute = "MaxInterval", Value = evt.MaxInterval });
            }
        }





        // 14 SubmodelElemente (+ OperationVariable)
        public override void VisitCapability(ICapability that)
        {
            CreateSMESet(that);
            base.VisitCapability(that);
        }
        public override void VisitRelationshipElement(IRelationshipElement that)
        {
            CreateSMESet(that);
            base.VisitRelationshipElement(that);
        }
        public override void VisitSubmodelElementList(ISubmodelElementList that)
        {
            var smeSet = CreateSMESet(that);
            _parSME = smeSet;
            base.VisitSubmodelElementList(that);
            _parSME = smeSet.ParentSME;
        }
        public override void VisitSubmodelElementCollection(ISubmodelElementCollection that)
        {
            var smeSet = CreateSMESet(that);
            _parSME = smeSet;
            base.VisitSubmodelElementCollection(that);
            _parSME = smeSet.ParentSME;
        }
        public override void VisitProperty(IProperty that)
        {
            CreateSMESet(that);
            base.VisitProperty(that);
        }
        public override void VisitMultiLanguageProperty(IMultiLanguageProperty that)
        {
            CreateSMESet(that);
            base.VisitMultiLanguageProperty(that);
        }
        public override void VisitRange(IRange that)
        {
            CreateSMESet(that);
            base.VisitRange(that);
        }
        public override void VisitReferenceElement(IReferenceElement that)
        {
            CreateSMESet(that);
            base.VisitReferenceElement(that);
        }
        public override void VisitBlob(IBlob that)
        {
            CreateSMESet(that);
            base.VisitBlob(that);
        }
        public override void VisitFile(IFile that)
        {
            CreateSMESet(that);
            base.VisitFile(that);
        }
        public override void VisitAnnotatedRelationshipElement(IAnnotatedRelationshipElement that)
        {
            var smeSet = CreateSMESet(that);
            _parSME = smeSet;
            base.VisitAnnotatedRelationshipElement(that);
            _parSME = smeSet.ParentSME;
        }
        public override void VisitEntity(IEntity that)
        {
            var smeSet = CreateSMESet(that);
            _parSME = smeSet;
            base.VisitEntity(that);
            _parSME = smeSet.ParentSME;
        }
        public override void VisitBasicEventElement(IBasicEventElement that)
        {
            CreateSMESet(that);
            base.VisitBasicEventElement(that);
        }
        public override void VisitOperation(IOperation that)
        {
            var smeSet = CreateSMESet(that);
            _parSME = smeSet;

            if (that.InputVariables != null)
            {
                _oprPrefix = OPERATION_INPUT + OPERATION_SPLIT;
                foreach (var item in that.InputVariables)
                    base.VisitOperationVariable(item);
            }

            if (that.OutputVariables != null)
            {
                _oprPrefix = OPERATION_OUTPUT + OPERATION_SPLIT;
                foreach (var item in that.OutputVariables)
                    base.VisitOperationVariable(item);
            }

            if (that.InoutputVariables != null)
            {
                _oprPrefix = OPERATION_INOUTPUT + OPERATION_SPLIT;
                foreach (var item in that.InoutputVariables)
                    base.VisitOperationVariable(item);
            }

            _oprPrefix = string.Empty;
            _parSME = smeSet.ParentSME;
        }
        public override void VisitOperationVariable(IOperationVariable that)
        {
            base.VisitOperationVariable(that);
        }





        // Not used
        public override void VisitEventPayload(IEventPayload that)
        {
            // base.VisitEventPayload(that);
        }
        public override void VisitReference(IReference that)
        {
            // base.VisitReference(that);
        }
        public override void VisitKey(IKey that)
        {
            // base.VisitKey(that);
        }
        public override void VisitEnvironment(IEnvironment that)
        {
            // base.VisitEnvironment(that);
        }
        public override void VisitLangStringNameType(ILangStringNameType that)
        {
            // base.VisitLangStringNameType(that);
        }
        public override void VisitLangStringTextType(ILangStringTextType that)
        {
            // base.VisitLangStringTextType(that);
        }
        public override void VisitEmbeddedDataSpecification(IEmbeddedDataSpecification that)
        {
            // if (that != null && that.DataSpecification != null)
            // base.VisitEmbeddedDataSpecification(that);
        }
        public override void VisitLevelType(ILevelType that)
        {
            // base.VisitLevelType(that);
        }
        public override void VisitValueReferencePair(IValueReferencePair that)
        {
            // base.VisitValueReferencePair(that);
        }
        public override void VisitValueList(IValueList that)
        {
            // base.VisitValueList(that);
        }
        public override void VisitLangStringPreferredNameTypeIec61360(ILangStringPreferredNameTypeIec61360 that)
        {
            // base.VisitLangStringPreferredNameTypeIec61360(that);
        }
        public override void VisitLangStringShortNameTypeIec61360(ILangStringShortNameTypeIec61360 that)
        {
            // base.VisitLangStringShortNameTypeIec61360(that);
        }
        public override void VisitLangStringDefinitionTypeIec61360(ILangStringDefinitionTypeIec61360 that)
        {
            // base.VisitLangStringDefinitionTypeIec61360(that);
        }
        public override void VisitDataSpecificationIec61360(IDataSpecificationIec61360 that)
        {
            // base.VisitDataSpecificationIec61360(that);
        }
        public override void VisitExtension(IExtension that)
        {
            // base.VisitExtension(that);
        }
        public override void VisitAdministrativeInformation(IAdministrativeInformation that)
        {
            // base.VisitAdministrativeInformation(that);
        }
        public override void VisitQualifier(IQualifier that)
        {
            // base.VisitQualifier(that);
        }
        public override void VisitAssetInformation(IAssetInformation that)
        {
            // base.VisitAssetInformation(that);
        }
        public override void VisitResource(IResource that)
        {
            // base.VisitResource(that);
        }
        public override void VisitSpecificAssetId(ISpecificAssetId that)
        {
            //base.VisitSpecificAssetId(that);
        }
    }
}