package clinicaltrials.domain;

public class Participant extends DomainObject
{
    /**
     * The Participant name.
     */
    private String name;

    /**
     * The Participant address.
     * <p>
     * This property exercises a dependent single-valued, unidirectional reference.
     * </p>
     */
    private Address address;

    public Participant()
    {
    }

    /**
     * @return the Participant name
     */
    public String getName()
    {
        return name;
    }

    /**
     * @param name the name to set
     */
    public void setName(String name)
    {
        this.name = name;
    }

    /**
     * @return the Participant address
     */
    public Address getAddress()
    {
        return address;
    }

    /**
     * @param address the address to set
     */
    public void setAddress(Address address)
    {
        this.address = address;
    }
}
