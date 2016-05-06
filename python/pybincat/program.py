
import ConfigParser
from collections import defaultdict
import re
from pybincat.tools import parsers
from pybincat import PyBinCATException
from pybincat import mlbincat
import tempfile

class PyBinCATParseError(PyBinCATException):
    pass


class Program(object):
    re_val = re.compile("\((?P<region>[^,]+)\s*,\s*(?P<value>[x0-9a-fA-F_,=? ]+)\)")

    def __init__(self, states, edges, nodes):
        self.states = states
        self.edges = edges
        self.nodes = nodes
        self.logs = None

    @classmethod 
    def parse(cls, filename, logs=None):
        
        states = {}
        edges = defaultdict(list)
        nodes = {}

        config = ConfigParser.ConfigParser()
        config.read(filename)


        for section in config.sections():
            if section == 'edges':
                for edgename, edge in config.items(section):
                    src, dst = edge.split(' -> ')
                    edges[src].append(dst)
                continue
            elif section.startswith('address = '):
                m = self.re_val.match(section[10:])
                if m:
                    address = Value(m.group("region"), int(m.group("value"), 0))
                    state = State.parse(address, config.items(section))
                    states[address] = state
                    nodes[state.node_id] = address
                    continue
            raise PyBinCATException("Cannot parse section name (%r)" % section)

        program = cls(states, edges, nodes)
        if logs:
            program.logs = open(logs).read()
        return program

    @classmethod
    def from_analyze(cls, initfile):
        outfile = tempfile.NamedTemporaryFile()
        logfile = tempfile.NamedTemporaryFile()
        
        mlbincat.process(initfile, outfile.name, logfile.name)

        return Program.parse(outfile.name, logs=logfile.name)

    @classmethod
    def from_state(cls, state):
        initfile = tempfile.NamedTemporaryFile()
        initfile.write(str(state))
        initfile.close()
        
        return from_analyze(cls, initfile.name)

    def __getitem__(self, pc):
        return self.states[pc]

    def next_states(self, pc):
        node = self[pc].node_id
        return [ self[nn] for nn in self.edges.get(node,[]) ]
        

 State(object):
    def __init__(self, address, node_id=None):
        self.address = address
        self.node_id = node_id
        self.regions = defaultdict(dict)

    @classmethod
    def parse(cls, address, outputkv):
        """
        :param outputkv: list of (key, value) tuples for each property set by
            the analyzer at this EIP
        """
        node_id = None
        
        new_state = State(program, address)

        for i, (k, v) in enumerate(outputkv):
            if k == "id":
                new_state.node_id = v
                continue
            m = cls.re_region.match(k)
            if not m:
                raise PyBinCATException("Parsing error (entry %i, key=%r)" % (i, k))
            region = m.group("region")
            adrs = m.group("adrs")

            m = cls.re_valtaint.match(v)
            if not m:
                raise PyBinCATException("Parsing error (entry %i: value=%r)" % (i, v))
            kind = m.group("kind")
            val = m.group("value")
            taint = m.group("taint")

            new_state[region][adrs] = Value.parse(kind, val, taint)

    def __getitem__(self, item):
        return self.regions[item]

    def __getattr__(self, attr):
        try:
            return self.regions[attr]
        except KeyError:
            raise AttributeError(attr)

    re_region = re.compile("(?P<region>reg|mem)\s*\[(?P<adrs>[^]]+)\]")
    re_valtaint = re.compile("\((?P<kind>[^,]+)\s*,\s*(?P<value>[x0-9a-fA-F_,=? ]+)\s*(!\s*(?P<taint>[x0-9a-fA-F_,=? ]+))?.*\).*")


    def __eq__(self, other):
        if set(self.region.keys()) != set(other.region.keys()):
            return False
        for region in self.region.keys():
            self_region_keys = set(self.regions[region].keys())
            other_region_keys = set(other.regions[region].keys())
            if self_region_keys != other_region_keys:
                return False
            for key in self_region_keys:
                if (self.regions[region][key] != other.regions[region][key]):
                    return False
        return True

    def list_modified_keys(self, other):
        """
        Returns a set of (region, name) for which regions or tainting values
        differ between self and other.
        """
        results = set()
        regions = set(self.regions) | set(other.regions)
        for region in regions:
            sPr = self.regions[region]
            oPr = other.regions[region]
            sPrK = set(sPr)
            oPrK = set(oPr)

            results |= set((region, p) for p in sPrK ^ oPrK)
            results |= set((region, p) for p in oPrK & sPrK
                           if sPr[p] != oPr[p])

        return results

    def diff(self, other):
        res = [ "--- %s" % self, "+++ %s" % other) ]
        for region, address in self.listModifiedKeys(other):
            res.append("@@ %s %s @@" % (region, address))
            if address not in self.regions[region]:
                res.append("+ %s" % other.regions[region][address])
            elif address not in other.regions[region]:
                res.append("- %s" % self.regions[region][address])
            elif self.regions[region][address] != other.regions[region][address]:
                res.append("- %s" % self.regions[region][address])
                res.append("+ %s" % other.regions[region][address])
        return "\n".join(res)

    def __str__(self):
        #XXX
        return "[Not implemented :(]"
        
        

class Value(object):
    def __init__(self, region, value, vtop=0, vbot=0, taint=0, ttop=0, tbot=0):
        self.region = region.lower()
        self.value = value
        self.vtop = vtop
        self.vbot = vbot
        self.taint = taint
        self.ttop = ttop
        self.tbot = tbot

    @classmethod
    def parse(cls, region, s, t):
        value, vtop, vbot = parsers.parse_val(s)
        taint, ttop, tbot = parsers.parse_val(t) if t is not None else (0, 0, 0)
        return cls(region, value, vtop, vbot, taint, ttop, tbot)

    def __repr__(self):
        return "Value(%s, %s ! %s)" % (
            self.region,
            parsers.val2str(self.value, self.vtop, self.vbot),
            parsers.val2str(self.taint, self.ttop, self.tbot))

    def __hash__(self):
        return hash((type(self), self.region, self.value,
                     self.vtop, self.vbot, self.taint,
                     self.ttop, self.tbot))

    def __eq__(self, other):
        return (self.region == other.region and
                self.value == other.value and self.taint == other.taint and
                self.vtop == other.vtop and self.ttop == other.ttop and
                self.vbot == other.vbot and self.tbot == other.tbot)

    def __ne__(self, other):
        return not (self == other)

    def __add__(self, other):
        other = getattr(other, "value", other)
        return self.__class__(self.region, self.value+other,
                              self.vtop, self.vbot, self.taint,
                              self.ttop, self.tbot)

    def __sub__(self, other):
        other = getattr(other, "value", other)
        return self.__class__(self.region, self.value-other,
                              self.vtop, self.vbot, self.taint,
                              self.ttop, self.tbot)

    def is_concrete(self):
        return self.vtop == 0 and self.vbot == 0

